from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from typing import Literal, Optional

from app.api.dependencies import get_db, get_current_user
from app.db.models import AppUser, Park, ParkNotice
from app.services.citizen import as_utc, refresh_park

router = APIRouter()


class ParkBody(BaseModel):
    name: str
    city: str = 'Legnano'
    address: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None


@router.get("/")
def list_parks(db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user)):
    parks = db.query(Park).filter(Park.active == True).order_by(Park.name).all()  # noqa: E712
    return [_fmt(p) for p in parks]


@router.post("/")
def create_park(body: ParkBody, db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user)):
    if current_user.type.value != 'admin':
        raise HTTPException(403, "Solo admin può creare parchi")
    p = Park(**body.model_dump())
    db.add(p); db.commit(); db.refresh(p)
    return _fmt(p)


# --- Avvisi per i cittadini (mostrati nell'app) -------------------------------
# admin: tutti i livelli; op_eco: info e warning. 'alert' porta lo stato del parco
# ad "Attenzione" nell'app, quindi lo decide solo un admin.

NoticeLevel = Literal["info", "warning", "alert"]


class NoticeBody(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    body: str = Field(min_length=1, max_length=1000)
    level: NoticeLevel = "info"
    starts_at: Optional[datetime] = None  # assente = subito
    ends_at: Optional[datetime] = None    # assente = finché non lo si toglie


class NoticePatch(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=120)
    body: Optional[str] = Field(None, min_length=1, max_length=1000)
    level: Optional[NoticeLevel] = None
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None  # null esplicito = nessuna fine


def _can_manage(user: AppUser, level: str) -> bool:
    t = user.type.value
    return t == 'admin' or (t == 'op_eco' and level in ('info', 'warning'))


def _check_manage(user: AppUser, level: str):
    if not _can_manage(user, level):
        raise HTTPException(403, "Solo un admin può gestire gli avvisi di livello 'alert'"
                                 if user.type.value == 'op_eco' else "Non puoi gestire gli avvisi del parco")


def _clean(title: Optional[str], body: Optional[str]):
    title = title.strip() if title is not None else None
    body = body.strip() if body is not None else None
    if title == "" or body == "":
        raise HTTPException(422, "Titolo e testo non possono essere vuoti")
    return title, body


def _check_window(starts_at: datetime, ends_at: Optional[datetime]):
    if ends_at is not None and as_utc(ends_at) <= as_utc(starts_at):
        raise HTTPException(422, "La fine dell'avviso deve essere dopo l'inizio")


def _get_park(db, park_id):
    p = db.query(Park).filter(Park.id == park_id).first()
    if not p: raise HTTPException(404, "Parco non trovato")
    return p


def _get_notice(db, park_id, notice_id):
    n = db.query(ParkNotice).filter(ParkNotice.id == notice_id, ParkNotice.park_id == park_id).first()
    if not n: raise HTTPException(404, "Avviso non trovato")
    return n


def _fmt_notice(n, now, authors):
    starts, ends = as_utc(n.starts_at), as_utc(n.ends_at) if n.ends_at else None
    return {
        "id": n.id, "park_id": n.park_id, "title": n.title, "body": n.body, "level": n.level,
        "starts_at": starts, "ends_at": ends,
        "state": "expired" if ends and ends <= now else "scheduled" if starts > now else "active",
        "created_by": authors.get(n.created_by), "created_at": as_utc(n.created_at) if n.created_at else None,
    }


def _authors(db, notices):
    ids = {n.created_by for n in notices if n.created_by}
    return dict(db.query(AppUser.id, AppUser.username).filter(AppUser.id.in_(ids))) if ids else {}


@router.get("/{park_id}/notices")
def list_notices(
    park_id: int,
    include_expired: bool = Query(False),
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    """Avvisi del parco per la dashboard: in corso e programmati (anche scaduti con include_expired)."""
    _get_park(db, park_id)
    now = datetime.now(timezone.utc)
    q = db.query(ParkNotice).filter(ParkNotice.park_id == park_id)
    if not include_expired:
        q = q.filter(or_(ParkNotice.ends_at.is_(None), ParkNotice.ends_at > now))
    rows = q.order_by(ParkNotice.starts_at.desc(), ParkNotice.id.desc()).limit(200).all()
    authors = _authors(db, rows)
    return [_fmt_notice(n, as_utc(now), authors) for n in rows]


@router.post("/{park_id}/notices", status_code=201)
def create_notice(park_id: int, body: NoticeBody, db: Session = Depends(get_db),
                  current_user: AppUser = Depends(get_current_user)):
    _get_park(db, park_id)
    _check_manage(current_user, body.level)
    title, text = _clean(body.title, body.body)
    now = datetime.now(timezone.utc)
    starts_at = as_utc(body.starts_at) if body.starts_at else now
    ends_at = as_utc(body.ends_at) if body.ends_at else None
    _check_window(starts_at, ends_at)
    n = ParkNotice(park_id=park_id, title=title, body=text, level=body.level, starts_at=starts_at,
                   ends_at=ends_at, created_by=current_user.id, created_at=now)
    db.add(n); db.commit(); db.refresh(n)
    refresh_park(db, park_id)  # notice_created ai cittadini se l'avviso è già in corso
    return _fmt_notice(n, as_utc(now), {current_user.id: current_user.username})


@router.patch("/{park_id}/notices/{notice_id}")
def update_notice(park_id: int, notice_id: int, body: NoticePatch, db: Session = Depends(get_db),
                  current_user: AppUser = Depends(get_current_user)):
    """Modifica parziale. Per far finire subito un avviso: {"ends_at": <adesso>}."""
    n = _get_notice(db, park_id, notice_id)
    _check_manage(current_user, n.level)
    fields = body.model_dump(exclude_unset=True)
    if fields.get("level") is not None:
        _check_manage(current_user, fields["level"])
    title, text = _clean(fields.get("title"), fields.get("body"))
    if title is not None: n.title = title
    if text is not None: n.body = text
    if fields.get("level") is not None: n.level = fields["level"]
    if fields.get("starts_at") is not None: n.starts_at = as_utc(fields["starts_at"])
    now = as_utc(datetime.now(timezone.utc))
    if "ends_at" in fields:
        ends_at = as_utc(fields["ends_at"]) if fields["ends_at"] else None
        if ends_at is not None and ends_at <= now:
            # "Termina ora": vale l'orologio del server, non quello del browser. Un avviso
            # ancora programmato finisce prima di iniziare e non compare mai.
            ends_at = now
            if as_utc(n.starts_at) > now:
                n.starts_at = now
        n.ends_at = ends_at
    if n.ends_at is None or as_utc(n.ends_at) > now:
        _check_window(n.starts_at, n.ends_at)
    db.commit(); db.refresh(n)
    refresh_park(db, park_id)
    return _fmt_notice(n, now, _authors(db, [n]))


@router.delete("/{park_id}/notices/{notice_id}")
def delete_notice(park_id: int, notice_id: int, db: Session = Depends(get_db),
                  current_user: AppUser = Depends(get_current_user)):
    n = _get_notice(db, park_id, notice_id)
    _check_manage(current_user, n.level)
    db.delete(n); db.commit()
    refresh_park(db, park_id)
    return {"ok": True}


@router.get("/{park_id}")
def get_park(park_id: int, db: Session = Depends(get_db), current_user: AppUser = Depends(get_current_user)):
    p = db.query(Park).filter(Park.id == park_id).first()
    if not p: raise HTTPException(404)
    return _fmt(p)


def _fmt(p):
    return {"id": p.id, "name": p.name, "city": p.city, "address": p.address, "lat": p.lat, "lon": p.lon}
