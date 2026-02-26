"""
dev.py -- DEV_MODE gated tamper + reset endpoints.
NEVER enable DEV_MODE=true in production.
These endpoints exist purely for experiment reproducibility.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.config   import DEV_MODE
from app.database import get_db
from app.models   import Event, Epoch, MmrNode, StagedEvent

router = APIRouter(tags=["dev"])


def _require_dev():
    if not DEV_MODE:
        raise HTTPException(status_code=403, detail="DEV_MODE is not enabled")


# ── reset org ─────────────────────────────────────────────────────────────────

@router.post("/dev/reset/{org_id}")
def dev_reset(org_id: str, db: Session = Depends(get_db)):
    """Wipe all data for an org. DEV_MODE only."""
    _require_dev()
    db.query(MmrNode).filter(MmrNode.org_id == org_id).delete()
    db.query(Epoch).filter(Epoch.org_id == org_id).delete()
    db.query(Event).filter(Event.org_id == org_id).delete()
    db.query(StagedEvent).filter(StagedEvent.org_id == org_id).delete()
    db.commit()
    return {"ok": True, "org_id": org_id, "action": "reset"}


# ── tamper committed event ────────────────────────────────────────────────────

@router.post("/tamper/{org_id}/{event_id}")
def tamper_event(org_id: str, event_id: str, db: Session = Depends(get_db)):
    """
    Mutate canonical_json of a committed event to simulate tampering.
    DEV_MODE only. Verification will fail after this.
    """
    _require_dev()
    event = db.query(Event).filter(
        Event.org_id   == org_id,
        Event.event_id == event_id,
    ).first()
    if event is None:
        raise HTTPException(status_code=404, detail=f"Event {event_id} not found")

    original = event.canonical_json
    event.canonical_json = original + "__TAMPERED__"
    db.commit()
    return {
        "ok":       True,
        "event_id": event_id,
        "action":   "tampered canonical_json",
        "note":     "leaf_hash in DB unchanged — verification will detect mismatch",
    }


# ── tamper epoch ──────────────────────────────────────────────────────────────

@router.post("/tamper-epoch/{org_id}/{epoch_id}")
def tamper_epoch(org_id: str, epoch_id: int, db: Session = Depends(get_db)):
    """
    Mutate epoch_hash of a finalized epoch to simulate epoch-level tampering.
    DEV_MODE only.
    """
    _require_dev()
    epoch = db.query(Epoch).filter(
        Epoch.org_id  == org_id,
        Epoch.epoch_id == epoch_id,
    ).first()
    if epoch is None:
        raise HTTPException(status_code=404, detail=f"Epoch {epoch_id} not found")

    original          = epoch.epoch_hash
    epoch.epoch_hash  = "ff" * 32   # deterministic garbage value
    db.commit()
    return {
        "ok":           True,
        "epoch_id":     epoch_id,
        "action":       "tampered epoch_hash",
        "original":     original,
        "replacement":  "ff" * 32,
    }


# ── delete committed event ────────────────────────────────────────────────────

@router.post("/dev/delete/{org_id}/{event_id}")
def dev_delete_event(org_id: str, event_id: str, db: Session = Depends(get_db)):
    """
    Hard-delete a committed event row (does NOT remove MMR nodes).
    Simulates a deletion attack. Verification will detect missing seq gap.
    DEV_MODE only.
    """
    _require_dev()
    event = db.query(Event).filter(
        Event.org_id   == org_id,
        Event.event_id == event_id,
    ).first()
    if event is None:
        raise HTTPException(status_code=404, detail=f"Event {event_id} not found")

    db.delete(event)
    db.commit()
    return {
        "ok":       True,
        "event_id": event_id,
        "action":   "hard deleted from events table",
        "note":     "MMR nodes remain — chain verification will detect orphan",
    }
