"""
agent.py -- POST /agent/propose and POST /agent/commit/{staged_id}
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.pipeline import propose, commit

router = APIRouter(prefix="/agent", tags=["agent"])


# ── request schemas ───────────────────────────────────────────────────────────

class ProposeRequest(BaseModel):
    org_id:        str
    agent_id:      str
    proposed_json: str   # raw JSON string — caller serializes their payload


# ── endpoints ─────────────────────────────────────────────────────────────────

@router.post("/propose")
def propose_event(req: ProposeRequest, db: Session = Depends(get_db)):
    """
    Phase 1 — store proposal, run policy checks, return decision.
    Always writes an auditable staged_events record.
    """
    try:
        staged = propose(
            db            = db,
            org_id        = req.org_id,
            agent_id      = req.agent_id,
            proposed_json = req.proposed_json,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {
        "staged_id":       staged.id,
        "org_id":          staged.org_id,
        "agent_id":        staged.agent_id,
        "status":          staged.status.value,
        "decision_reason": staged.decision_reason,
        "risk_score":      staged.risk_score,
        "policy_version":  staged.policy_version,
        "created_at":      staged.created_at.isoformat(),
    }


@router.post("/commit/{staged_id}")
def commit_event(staged_id: int, db: Session = Depends(get_db)):
    """
    Phase 2 — finalize an APPROVED staged event into the immutable ledger.
    Rejected or missing staged_id returns 400.
    """
    try:
        event = commit(db=db, staged_id=staged_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {
        "event_id":  event.event_id,
        "org_id":    event.org_id,
        "seq":       event.seq,
        "epoch_id":  event.epoch_id,
        "leaf_hash": event.leaf_hash,
        "created_at":event.created_at.isoformat(),
    }
