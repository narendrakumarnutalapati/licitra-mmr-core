"""
query.py -- GET /verify, /proof, /evidence, /evidence/pdf
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.database import get_db
from app.verify   import verify_org
from app.evidence import build_json_bundle, build_proof_for_event, build_pdf_bundle

router = APIRouter(tags=["query"])


@router.get("/verify/{org_id}")
def verify(
    org_id:       str,
    recompute_mmr: bool = Query(default=True, description="Recompute MMR root from stored nodes"),
    db:           Session = Depends(get_db),
):
    """Verify epoch hash chain integrity for an organization."""
    return verify_org(db, org_id, recompute_mmr=recompute_mmr)


@router.get("/proof/{org_id}/{event_id}")
def get_proof(org_id: str, event_id: str, db: Session = Depends(get_db)):
    """Return MMR inclusion proof for a specific committed event."""
    try:
        return build_proof_for_event(db, org_id, event_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.get("/evidence/{org_id}/pdf")
def get_evidence_pdf(org_id: str, db: Session = Depends(get_db)):
    """Return evidence bundle as a signed PDF."""
    try:
        pdf_bytes = build_pdf_bundle(db, org_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return Response(
        content     = pdf_bytes,
        media_type  = "application/pdf",
        headers     = {"Content-Disposition": f"attachment; filename=evidence_{org_id}.pdf"},
    )


@router.get("/evidence/{org_id}")
def get_evidence(org_id: str, db: Session = Depends(get_db)):
    """Return full evidence bundle as JSON."""
    try:
        return build_json_bundle(db, org_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
