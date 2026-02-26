"""
verify.py -- Epoch hash chain verification + MMR root recompute + leaf integrity check.
"""

from sqlalchemy.orm import Session
from app import canon, hashing, mmr as mmr_mod
from app.config import GENESIS_HASH, LEDGER_VERSION
from app.models import Epoch, Event, MmrNode


def _recompute_mmr_root(db: Session, org_id: str, epoch_id: int) -> str:
    rows = (
        db.query(MmrNode)
        .filter(MmrNode.org_id == org_id, MmrNode.epoch_id == epoch_id)
        .order_by(MmrNode.position)
        .all()
    )
    if not rows:
        raise ValueError(f"No MMR nodes for org={org_id} epoch={epoch_id}")
    max_pos = max(r.position for r in rows)
    nodes   = [""] * (max_pos + 1)
    for r in rows:
        nodes[r.position] = r.node_hash
    return mmr_mod.get_mmr_root(nodes)


def _verify_epoch_leaves(db: Session, org_id: str, epoch_id: int):
    """
    For every event in the epoch:
      1. recompute SHA256(canonical_json) and compare to stored leaf_hash
      2. confirm stored leaf_hash exists in mmr_nodes for that epoch
    Returns (ok: bool, reason: str | None, bad_event_id: str | None)
    """
    events = (
        db.query(Event)
        .filter(Event.org_id == org_id, Event.epoch_id == epoch_id)
        .order_by(Event.seq)
        .all()
    )

    # load mmr leaf hashes for fast lookup
    mmr_leaves = set(
        row.node_hash for row in
        db.query(MmrNode).filter(
            MmrNode.org_id   == org_id,
            MmrNode.epoch_id == epoch_id,
        ).all()
    )

    for event in events:
        # recompute leaf hash from stored canonical_json
        recomputed = hashing.hash_leaf(event.canonical_json.encode("utf-8"))

        if recomputed != event.leaf_hash:
            return (
                False,
                f"canonical_json does not match leaf_hash for event {event.event_id} "
                f"(seq={event.seq}): stored={event.leaf_hash} recomputed={recomputed}",
                event.event_id,
            )

        if event.leaf_hash not in mmr_leaves:
            return (
                False,
                f"leaf_hash not found in mmr_nodes for event {event.event_id} (seq={event.seq})",
                event.event_id,
            )

    return True, None, None


def verify_org(db: Session, org_id: str, recompute_mmr: bool = True) -> dict:
    """
    Full verification:
      1. Walk all finalized epochs
      2. Verify leaf integrity (canonical_json -> leaf_hash)
      3. Recompute MMR root from nodes
      4. Recompute epoch_hash and check chain linkage
    """
    epochs = (
        db.query(Epoch)
        .filter(Epoch.org_id == org_id)
        .order_by(Epoch.epoch_id)
        .all()
    )

    if not epochs:
        return {
            "org_id":          org_id,
            "ok":              True,
            "epochs":          0,
            "total_events":    0,
            "last_epoch_hash": None,
            "note":            "No finalized epochs yet",
        }

    prev_hash    = GENESIS_HASH
    total_events = 0

    for epoch in epochs:

        # ── 1. leaf integrity check ──────────────────────────────────────────
        leaf_ok, leaf_reason, bad_event = _verify_epoch_leaves(db, org_id, epoch.epoch_id)
        if not leaf_ok:
            return {
                "org_id":          org_id,
                "ok":              False,
                "bad_epoch_index": epoch.epoch_id,
                "bad_event_id":    bad_event,
                "reason":          f"Leaf integrity failure: {leaf_reason}",
                "epochs":          len(epochs),
                "total_events":    total_events,
                "last_epoch_hash": prev_hash,
            }

        # ── 2. MMR root recompute ────────────────────────────────────────────
        if recompute_mmr:
            try:
                computed_root = _recompute_mmr_root(db, org_id, epoch.epoch_id)
            except ValueError as e:
                return {
                    "org_id":          org_id,
                    "ok":              False,
                    "bad_epoch_index": epoch.epoch_id,
                    "reason":          f"MMR node load failed: {e}",
                    "epochs":          len(epochs),
                    "total_events":    total_events,
                    "last_epoch_hash": None,
                }
            if computed_root != epoch.mmr_root:
                return {
                    "org_id":          org_id,
                    "ok":              False,
                    "bad_epoch_index": epoch.epoch_id,
                    "reason":          f"MMR root mismatch: stored={epoch.mmr_root} computed={computed_root}",
                    "epochs":          len(epochs),
                    "total_events":    total_events,
                    "last_epoch_hash": None,
                }

        # ── 3. epoch_hash recompute ──────────────────────────────────────────
        meta = canon.canonical_bytes({
            "org_id":         org_id,
            "epoch_id":       epoch.epoch_id,
            "start_seq":      epoch.start_seq,
            "end_seq":        epoch.end_seq,
            "event_count":    epoch.event_count,
            "ledger_version": LEDGER_VERSION,
        })
        expected_hash = hashing.hash_epoch(prev_hash, epoch.mmr_root, meta)

        if expected_hash != epoch.epoch_hash:
            return {
                "org_id":          org_id,
                "ok":              False,
                "bad_epoch_index": epoch.epoch_id,
                "reason":          f"epoch_hash mismatch at epoch {epoch.epoch_id}",
                "epochs":          len(epochs),
                "total_events":    total_events,
                "last_epoch_hash": prev_hash,
            }

        # ── 4. prev_epoch_hash linkage ───────────────────────────────────────
        if epoch.prev_epoch_hash != prev_hash:
            return {
                "org_id":          org_id,
                "ok":              False,
                "bad_epoch_index": epoch.epoch_id,
                "reason":          f"prev_epoch_hash broken at epoch {epoch.epoch_id}",
                "epochs":          len(epochs),
                "total_events":    total_events,
                "last_epoch_hash": prev_hash,
            }

        prev_hash     = epoch.epoch_hash
        total_events += epoch.event_count

    return {
        "org_id":          org_id,
        "ok":              True,
        "epochs":          len(epochs),
        "total_events":    total_events,
        "last_epoch_hash": prev_hash,
    }
