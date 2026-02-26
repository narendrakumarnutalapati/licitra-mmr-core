"""
evidence.py -- JSON + PDF evidence bundle generation.
"""

import hashlib
import json
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app import canon, mmr as mmr_mod
from app.config import BLOCK_SIZE, LEDGER_VERSION
from app.models import Epoch, Event, MmrNode, StagedEvent, StagedStatus
from app.verify import verify_org


# ── JSON bundle ───────────────────────────────────────────────────────────────

def build_json_bundle(db: Session, org_id: str) -> dict:
    verification = verify_org(db, org_id, recompute_mmr=True)

    epochs = (
        db.query(Epoch)
        .filter(Epoch.org_id == org_id)
        .order_by(Epoch.epoch_id)
        .all()
    )

    last_events = (
        db.query(Event)
        .filter(Event.org_id == org_id)
        .order_by(Event.seq.desc())
        .limit(20)
        .all()
    )

    last_staged = (
        db.query(StagedEvent)
        .filter(StagedEvent.org_id == org_id)
        .order_by(StagedEvent.id.desc())
        .limit(20)
        .all()
    )

    # inclusion proof example from most recent committed event
    proof_example = None
    if last_events:
        sample = last_events[0]
        proof_example = _build_proof(db, org_id, sample)

    epoch_list = [
        {
            "epoch_id":       e.epoch_id,
            "start_seq":      e.start_seq,
            "end_seq":        e.end_seq,
            "event_count":    e.event_count,
            "mmr_root":       e.mmr_root,
            "prev_epoch_hash":e.prev_epoch_hash,
            "epoch_hash":     e.epoch_hash,
            "created_at":     e.created_at.isoformat(),
        }
        for e in epochs
    ]

    events_list = [
        {
            "event_id":  ev.event_id,
            "seq":       ev.seq,
            "epoch_id":  ev.epoch_id,
            "leaf_hash": ev.leaf_hash,
            "created_at":ev.created_at.isoformat(),
        }
        for ev in reversed(last_events)
    ]

    staged_list = [
        {
            "id":              s.id,
            "agent_id":        s.agent_id,
            "status":          s.status.value,
            "decision_reason": s.decision_reason,
            "risk_score":      s.risk_score,
            "policy_version":  s.policy_version,
            "created_at":      s.created_at.isoformat(),
        }
        for s in last_staged
    ]

    bundle = {
        "summary": {
            "org_id":           org_id,
            "ledger_version":   LEDGER_VERSION,
            "hash_alg":         "SHA256",
            "block_size":       BLOCK_SIZE,
            "verified_at":      datetime.now(timezone.utc).isoformat(),
            "ok":               verification["ok"],
            "epochs":           verification["epochs"],
            "total_events":     verification["total_events"],
            "last_epoch_hash":  verification.get("last_epoch_hash"),
            "bad_epoch_index":  verification.get("bad_epoch_index"),
            "reason":           verification.get("reason"),
        },
        "epochs":          epoch_list,
        "last_20_events":  events_list,
        "proof_example":   proof_example,
        "last_20_staged":  staged_list,
    }

    # self-checksum (excludes bundle_sha256 key itself)
    raw        = canon.canonical_bytes(bundle)
    bundle_sha = hashlib.sha256(raw).hexdigest()
    bundle["summary"]["bundle_sha256"] = bundle_sha

    return bundle


# ── inclusion proof ───────────────────────────────────────────────────────────

def _build_proof(db: Session, org_id: str, event: Event) -> Optional[dict]:
    # only build proof for finalized epochs
    epoch_row = db.query(Epoch).filter(
        Epoch.org_id   == org_id,
        Epoch.epoch_id == event.epoch_id,
    ).first()
    if epoch_row is None:
        return None

    nodes = _load_nodes(db, org_id, event.epoch_id)
    if not nodes:
        return None

    # find leaf position by matching leaf_hash
    try:
        leaf_pos = nodes.index(event.leaf_hash)
    except ValueError:
        return None

    try:
        proof_path = mmr_mod.get_proof(leaf_pos, nodes)
        mmr_root   = mmr_mod.get_mmr_root(nodes)
    except Exception:
        return None

    return {
        "org_id":     org_id,
        "event_id":   event.event_id,
        "epoch_id":   event.epoch_id,
        "leaf_hash":  event.leaf_hash,
        "mmr_root":   mmr_root,
        "proof_path": proof_path,
        "epoch_hash": epoch_row.epoch_hash if epoch_row else None,
    }


def build_proof_for_event(db: Session, org_id: str, event_id: str) -> dict:
    event = db.query(Event).filter(
        Event.org_id  == org_id,
        Event.event_id == event_id,
    ).first()
    if event is None:
        raise ValueError(f"Event {event_id} not found for org {org_id}")
    proof = _build_proof(db, org_id, event)
    if proof is None:
        raise ValueError(f"Could not build proof for event {event_id}")
    return proof


def _load_nodes(db: Session, org_id: str, epoch_id: int) -> list:
    rows = (
        db.query(MmrNode)
        .filter(MmrNode.org_id == org_id, MmrNode.epoch_id == epoch_id)
        .order_by(MmrNode.position)
        .all()
    )
    if not rows:
        return []
    max_pos = max(r.position for r in rows)
    nodes   = [""] * (max_pos + 1)
    for r in rows:
        nodes[r.position] = r.node_hash
    return nodes


# ── PDF bundle ────────────────────────────────────────────────────────────────

def build_pdf_bundle(db: Session, org_id: str) -> bytes:
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable
    from reportlab.lib import colors
    import io

    bundle = build_json_bundle(db, org_id)
    summary = bundle["summary"]

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4,
                            leftMargin=20*mm, rightMargin=20*mm,
                            topMargin=20*mm, bottomMargin=20*mm)
    styles = getSampleStyleSheet()
    mono   = ParagraphStyle("mono", fontName="Courier", fontSize=7, leading=10)
    h1     = styles["h1"]
    h2     = styles["h2"]
    normal = styles["Normal"]
    story  = []

    def hr():
        story.append(HRFlowable(width="100%", thickness=0.5, color=colors.grey))
        story.append(Spacer(1, 4*mm))

    def kv(k, v):
        story.append(Paragraph(f"<b>{k}:</b> {v}", normal))

    # ── Title ──
    story.append(Paragraph("LICITRA-MMR Evidence Bundle", h1))
    story.append(Paragraph(f"Organization: {org_id}", h2))
    hr()

    # ── Summary ──
    story.append(Paragraph("Summary", h2))
    kv("Ledger Version",  summary["ledger_version"])
    kv("Hash Algorithm",  summary["hash_alg"])
    kv("Block Size",      summary["block_size"])
    kv("Verified At",     summary["verified_at"])
    ok_str = "✓ VERIFIED" if summary["ok"] else "✗ TAMPERED"
    kv("Integrity",       ok_str)
    kv("Total Epochs",    summary["epochs"])
    kv("Total Events",    summary["total_events"])
    kv("Last Epoch Hash", summary.get("last_epoch_hash") or "N/A")
    if not summary["ok"]:
        kv("Bad Epoch Index", summary.get("bad_epoch_index"))
        kv("Failure Reason",  summary.get("reason"))
    kv("Bundle SHA-256",  summary.get("bundle_sha256"))
    hr()

    # ── Epoch chain head/tail ──
    story.append(Paragraph("Epoch Hash Chain", h2))
    epochs = bundle["epochs"]
    display_epochs = (epochs[:3] + epochs[-3:]) if len(epochs) > 6 else epochs
    for e in display_epochs:
        story.append(Paragraph(
            f"Epoch {e['epoch_id']} | seqs {e['start_seq']}–{e['end_seq']} | "
            f"events={e['event_count']}", normal))
        story.append(Paragraph(f"  mmr_root:   {e['mmr_root']}", mono))
        story.append(Paragraph(f"  epoch_hash: {e['epoch_hash']}", mono))
        story.append(Spacer(1, 2*mm))
    hr()

    # ── Proof example ──
    story.append(Paragraph("Inclusion Proof Example", h2))
    proof = bundle.get("proof_example")
    if proof:
        kv("Event ID",  proof["event_id"])
        kv("Epoch ID",  proof["epoch_id"])
        kv("Leaf Hash", proof["leaf_hash"])
        kv("MMR Root",  proof["mmr_root"])
        kv("Epoch Hash",proof.get("epoch_hash") or "N/A")
        story.append(Paragraph(f"Proof path steps: {len(proof['proof_path'])}", normal))
        for i, step in enumerate(proof["proof_path"]):
            story.append(Paragraph(f"  [{i}] side={step['side']} hash={step['hash']}", mono))
    else:
        story.append(Paragraph("No proof available (epoch not yet finalized).", normal))
    hr()

    # ── Staged decisions summary ──
    story.append(Paragraph("Last 20 Staged Decisions (Audit Narrative)", h2))
    staged = bundle.get("last_20_staged", [])
    if staged:
        tdata  = [["ID", "Agent", "Status", "Risk", "Reason"]]
        for s in staged:
            tdata.append([
                str(s["id"]),
                str(s["agent_id"])[:20],
                s["status"],
                f"{s['risk_score']:.3f}" if s["risk_score"] is not None else "—",
                str(s["decision_reason"])[:60],
            ])
        t = Table(tdata, repeatRows=1, hAlign="LEFT",
                  colWidths=[12*mm, 35*mm, 22*mm, 15*mm, 80*mm])
        t.setStyle(TableStyle([
            ("BACKGROUND", (0,0), (-1,0), colors.HexColor("#333333")),
            ("TEXTCOLOR",  (0,0), (-1,0), colors.white),
            ("FONTSIZE",   (0,0), (-1,-1), 7),
            ("FONTNAME",   (0,0), (-1,0), "Helvetica-Bold"),
            ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, colors.HexColor("#f5f5f5")]),
            ("GRID",       (0,0), (-1,-1), 0.3, colors.grey),
            ("VALIGN",     (0,0), (-1,-1), "TOP"),
        ]))
        story.append(t)
    else:
        story.append(Paragraph("No staged decisions recorded.", normal))

    doc.build(story)
    return buf.getvalue()

