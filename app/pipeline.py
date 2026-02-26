"""
pipeline.py -- Two-phase commit pipeline: propose + commit.

Phase 1: propose()  -> writes staged_events, runs policy, returns result
Phase 2: commit()   -> converts approved staged event into committed event + MMR append
"""

import uuid
import json
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session
from sqlalchemy import func

from app import canon, hashing, mmr as mmr_mod, policy as policy_mod
from app.config import BLOCK_SIZE, EMIT_BLOCKED_ACTION, POLICY_VERSION, GENESIS_HASH, LEDGER_VERSION
from app.models import StagedEvent, StagedStatus, Event, Epoch, MmrNode


# ── helpers ───────────────────────────────────────────────────────────────────

def _next_seq(db: Session, org_id: str) -> int:
    """DB-assigned per-org monotonic sequence. Locks row to prevent races."""
    row = db.execute(
        __import__("sqlalchemy").text(
            "SELECT COALESCE(MAX(seq), 0) + 1 AS next_seq FROM events WHERE org_id = :org"
        ),
        {"org": org_id},
    ).fetchone()
    return int(row.next_seq)


def _current_epoch_id(db: Session, org_id: str) -> int:
    """Return the epoch_id that should receive the next event."""
    row = db.execute(
        __import__("sqlalchemy").text(
            "SELECT COALESCE(MAX(epoch_id), 0) AS max_epoch FROM events WHERE org_id = :org"
        ),
        {"org": org_id},
    ).fetchone()
    candidate = int(row.max_epoch)

    # check if that epoch is already finalized (full)
    finalized = db.query(Epoch).filter(
        Epoch.org_id == org_id,
        Epoch.epoch_id == candidate,
    ).first()

    if finalized is not None:
        return candidate + 1
    return candidate


def _load_mmr_nodes(db: Session, org_id: str, epoch_id: int) -> list:
    """Load ordered MMR node hashes for an epoch."""
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


def _epoch_event_count(db: Session, org_id: str, epoch_id: int) -> int:
    return db.query(Event).filter(
        Event.org_id  == org_id,
        Event.epoch_id == epoch_id,
    ).count()


def _prev_epoch_hash(db: Session, org_id: str, epoch_id: int) -> str:
    if epoch_id == 0:
        return GENESIS_HASH
    prev = db.query(Epoch).filter(
        Epoch.org_id  == org_id,
        Epoch.epoch_id == epoch_id - 1,
    ).first()
    if prev is None:
        return GENESIS_HASH
    return prev.epoch_hash


# ── epoch finalization ────────────────────────────────────────────────────────

def _finalize_epoch(db: Session, org_id: str, epoch_id: int) -> Epoch:
    """Compute and persist epoch row. Called when epoch reaches BLOCK_SIZE."""
    nodes = _load_mmr_nodes(db, org_id, epoch_id)
    mmr_root = mmr_mod.get_mmr_root(nodes)

    events_in_epoch = (
        db.query(Event)
        .filter(Event.org_id == org_id, Event.epoch_id == epoch_id)
        .order_by(Event.seq)
        .all()
    )
    start_seq = events_in_epoch[0].seq
    end_seq   = events_in_epoch[-1].seq
    count     = len(events_in_epoch)

    meta = canon.canonical_bytes({
        "org_id":         org_id,
        "epoch_id":       epoch_id,
        "start_seq":      start_seq,
        "end_seq":        end_seq,
        "event_count":    count,
        "ledger_version": LEDGER_VERSION,
    })

    prev_hash  = _prev_epoch_hash(db, org_id, epoch_id)
    epoch_hash = hashing.hash_epoch(prev_hash, mmr_root, meta)

    epoch_row = Epoch(
        org_id          = org_id,
        epoch_id        = epoch_id,
        start_seq       = start_seq,
        end_seq         = end_seq,
        mmr_root        = mmr_root,
        prev_epoch_hash = prev_hash,
        epoch_hash      = epoch_hash,
        event_count     = count,
    )
    db.add(epoch_row)
    db.flush()
    return epoch_row


# ── Phase 1: propose ──────────────────────────────────────────────────────────

def propose(
    db:            Session,
    org_id:        str,
    agent_id:      str,
    proposed_json: str,
) -> StagedEvent:
    """
    Store proposal, run policy, persist decision, return staged row.
    Always writes an auditable record regardless of outcome.
    """
    result = policy_mod.evaluate(proposed_json)

    staged = StagedEvent(
        org_id          = org_id,
        agent_id        = agent_id,
        proposed_json   = proposed_json,
        status          = StagedStatus(result.status),
        decision_reason = result.reason,
        risk_score      = result.risk_score,
        policy_version  = POLICY_VERSION,
    )
    db.add(staged)
    db.flush()   # get staged.id without full commit

    # if rejected and EMIT_BLOCKED_ACTION is on -> commit a blocked_action audit event
    if result.status == "REJECTED" and EMIT_BLOCKED_ACTION:
        _commit_blocked_action(db, org_id, agent_id, staged.id, proposed_json, result.reason)

    db.commit()
    db.refresh(staged)
    return staged


# ── blocked action helper ─────────────────────────────────────────────────────

def _commit_blocked_action(
    db:            Session,
    org_id:        str,
    agent_id:      str,
    staged_id:     int,
    proposed_json: str,
    reason:        str,
) -> Event:
    """Commit a 'blocked_action' audit event into the MMR for rejected proposals."""
    audit_payload = {
        "action_type": "blocked_action",
        "agent_id":    agent_id,
        "staged_id":   staged_id,
        "reason":      reason,
        "original_proposed_json": proposed_json,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
    }
    return _insert_event(db, org_id, str(uuid.uuid4()), audit_payload)


# ── Phase 2: commit ───────────────────────────────────────────────────────────

def commit(db: Session, staged_id: int) -> Event:
    """
    Finalize an APPROVED staged event into the immutable ledger.
    Raises ValueError if not found or not APPROVED.
    """
    staged = db.query(StagedEvent).filter(StagedEvent.id == staged_id).first()
    if staged is None:
        raise ValueError(f"staged_id {staged_id} not found")
    if staged.status != StagedStatus.APPROVED:
        raise ValueError(f"staged_id {staged_id} has status {staged.status.value}, must be APPROVED")

    payload = json.loads(staged.proposed_json)
    event   = _insert_event(db, staged.org_id, str(uuid.uuid4()), payload)
    db.commit()
    return event


# ── core insert + MMR append ──────────────────────────────────────────────────

def _insert_event(
    db:       Session,
    org_id:   str,
    event_id: str,
    payload:  dict,
) -> Event:
    """
    Canonicalize payload, assign seq, append to MMR, persist event.
    Handles epoch finalization if BLOCK_SIZE is reached.
    Internal — always call within an open transaction.
    """
    canonical_str   = canon.canonical_dumps(payload)
    canonical_b     = canonical_str.encode("utf-8")
    leaf_hash       = hashing.hash_leaf(canonical_b)

    seq      = _next_seq(db, org_id)
    epoch_id = _current_epoch_id(db, org_id)

    # load existing MMR nodes for this epoch
    existing_nodes = _load_mmr_nodes(db, org_id, epoch_id)

    # append leaf
    updated_nodes, new_nodes = mmr_mod.append_leaf(leaf_hash, existing_nodes)

    # persist new MMR nodes
    for pos, node_hash in new_nodes:
        db.add(MmrNode(
            org_id    = org_id,
            epoch_id  = epoch_id,
            position  = pos,
            node_hash = node_hash,
        ))

    # persist event
    event = Event(
        org_id         = org_id,
        event_id       = event_id,
        seq            = seq,
        canonical_json = canonical_str,
        leaf_hash      = leaf_hash,
        epoch_id       = epoch_id,
    )
    db.add(event)
    db.flush()

    # check if epoch is now full
    count = _epoch_event_count(db, org_id, epoch_id) 
    if count >= BLOCK_SIZE:
        _finalize_epoch(db, org_id, epoch_id)

    return event
