"""API operatori per suggerimenti e feedback dei cittadini (prefisso /citizen-reports).
I problemi non passano di qui: diventano pratiche e il loro stato segue la pratica."""
from datetime import datetime, timezone
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.dependencies import get_db, get_current_user
from app.db.models import AppUser, CitizenCategory, CitizenReport
from app.services import citizen as svc

router = APIRouter()

KINDS = ("suggestion", "feedback")


class ReportStatusBody(BaseModel):
    status: Literal["received", "in_progress", "resolved", "closed"]
    citizen_note: Optional[str] = Field(None, max_length=500)  # visibile al cittadino


def _admin(user: AppUser):
    if user.type.value != "admin":
        raise HTTPException(403, "Solo admin può gestire suggerimenti e feedback")


def _fmt(r, labels):
    return {
        "id": r.id, "code": svc.report_code(r), "kind": r.kind,
        "category": r.category, "category_label": labels.get(r.category) if r.category else None,
        "title": r.title, "visibility": r.visibility,
        "description": r.description, "rating": r.rating,
        "lat": r.lat, "lon": r.lon, "photo_url": svc.photo_url(r.photo_path),
        "status": r.status, "status_label": svc.STATUS_LABELS[r.status],
        "created_at": svc.as_utc(r.created_at), "updated_at": svc.as_utc(r.updated_at or r.created_at),
    }


@router.get("/")
def list_reports(
    kind: Optional[Literal["suggestion", "feedback"]] = None,
    status: Optional[Literal["received", "in_progress", "resolved", "closed"]] = None,
    park_id: Optional[int] = None,
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Suggerimenti e feedback, dai più recenti. Mai l'identificativo del cittadino."""
    _admin(current_user)
    q = db.query(CitizenReport).filter(CitizenReport.kind.in_([kind] if kind else KINDS))
    if status:
        q = q.filter(CitizenReport.status == status)
    if park_id is not None:
        q = q.filter(CitizenReport.park_id == park_id)
    total = q.count()
    rows = q.order_by(CitizenReport.created_at.desc(), CitizenReport.id.desc()).offset(skip).limit(limit).all()
    labels = dict(db.query(CitizenCategory.code, CitizenCategory.label))
    return {"items": [_fmt(r, labels) for r in rows], "total": total}


@router.patch("/{report_id}/status")
def update_status(
    report_id: int,
    body: ReportStatusBody,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _admin(current_user)
    r = db.query(CitizenReport).filter(CitizenReport.id == report_id, CitizenReport.kind.in_(KINDS)).first()
    if r is None:
        raise HTTPException(404, "Suggerimento o feedback non trovato")
    note = (body.citizen_note or "").strip() or None
    if r.status != body.status or note:
        svc.set_status(r, body.status, note, datetime.now(timezone.utc))
        db.commit()
        svc.notify_reports([r])
    labels = dict(db.query(CitizenCategory.code, CitizenCategory.label))
    return _fmt(r, labels)
