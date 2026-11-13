"""API dell'app del cittadino (prefisso /citizen). Usano solo il token del
cittadino e non restituiscono mai dati interni: vedi CITIZEN_API_DESIGN.md."""
import copy, hashlib, secrets, string, threading, time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, Response, UploadFile, WebSocket, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.api.dependencies import get_db, get_current_citizen, citizen_from_token
from app.core.citizen_ws import citizen_ws_manager
from app.core.config import settings
from app.db.database import SessionLocal
from app.core.security import create_access_token, CITIZEN_SCOPE
from app.db.models import Citizen, CitizenCategory, CitizenReport, CitizenReportHistory, CitizenIdeaVote, Park
from app.schemas.citizen import (
    CitizenRegister, CitizenSession, CitizenPark, CitizenCategoryOut, ParkNoticeOut, ParkStatus,
    ReportCreated, ReportDetail, ReportHistoryItem, ReportPage, ReportSummary,
    IdeaCreate, IdeaOut, IdeaPage, IdeaVoteResult,
)
from app.services import citizen as svc
from app.services.correlation import _hav

router = APIRouter()

PUBLIC_ID_ALPHABET = string.ascii_letters + string.digits

# Registrazioni per IP nell'ultima ora. In memoria: c'è un solo worker uvicorn.
# L'IP è quello della connessione, non X-Forwarded-For (falsificabile).
_register_hits: dict[str, deque] = defaultdict(deque)
_register_lock = threading.Lock()


def _check_register_rate(ip: str) -> None:
    now = time.monotonic()
    with _register_lock:
        hits = _register_hits[ip]
        while hits and now - hits[0] > 3600:
            hits.popleft()
        if len(hits) >= settings.CITIZEN_REGISTER_PER_HOUR:
            retry_after = int(3600 - (now - hits[0])) + 1
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                "Troppe registrazioni da questa rete, riprova più tardi",
                headers={"Retry-After": str(retry_after)},
            )
        hits.append(now)


def _new_public_id(db: Session) -> str:
    while True:
        public_id = "c_" + "".join(secrets.choice(PUBLIC_ID_ALPHABET) for _ in range(8))
        if not db.query(Citizen.id).filter(Citizen.public_id == public_id).first():
            return public_id


@router.post(
    "/register",
    response_model=CitizenSession,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "Installazione già registrata: stesso cittadino, nuovo token"}},
)
def register(body: CitizenRegister, request: Request, response: Response, db: Session = Depends(get_db)):
    """Registra l'installazione anonima e restituisce il token. Con lo stesso
    install_id si ottiene sempre lo stesso cittadino (e lo stesso storico)."""
    _check_register_rate(request.client.host if request.client else "unknown")
    install_hash = hashlib.sha256(str(body.install_id).encode()).hexdigest()

    citizen = db.query(Citizen).filter(Citizen.install_hash == install_hash).first()
    if citizen is None:
        citizen = Citizen(public_id=_new_public_id(db), install_hash=install_hash, blocked=False,
                          platform=body.platform, app_version=body.app_version)
        db.add(citizen)
        try:
            db.commit()
        except IntegrityError:
            # Due registrazioni simultanee dello stesso install_id: vince la prima
            db.rollback()
            citizen = db.query(Citizen).filter(Citizen.install_hash == install_hash).one()
            response.status_code = status.HTTP_200_OK
    else:
        response.status_code = status.HTTP_200_OK
        citizen.platform, citizen.app_version = body.platform, body.app_version
        db.commit()

    if citizen.blocked:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Questa installazione è stata bloccata")

    expires = timedelta(days=settings.CITIZEN_TOKEN_EXPIRE_DAYS)
    token = create_access_token(
        data={"sub": f"citizen:{citizen.public_id}", "scope": CITIZEN_SCOPE}, expires_delta=expires
    )
    return CitizenSession(citizen_id=citizen.public_id, access_token=token,
                          expires_in=int(expires.total_seconds()))


@router.get("/parks", response_model=list[CitizenPark])
def list_parks(db: Session = Depends(get_db), citizen: Citizen = Depends(get_current_citizen)):
    """Parchi attivi. In ordine di id: nell'MVP l'app usa il primo della lista."""
    parks = db.query(Park).filter(Park.active == True).order_by(Park.id).all()  # noqa: E712
    return [CitizenPark(id=p.id, name=p.name, city=p.city, lat=p.lat, lon=p.lon) for p in parks]


def _active_park(db: Session, park_id: int) -> Park:
    park = db.query(Park).filter(Park.id == park_id, Park.active == True).first()  # noqa: E712
    if park is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Parco non trovato")
    return park


@router.get("/parks/{park_id}/status", response_model=ParkStatus)
def get_park_status(park_id: int, db: Session = Depends(get_db), citizen: Citizen = Depends(get_current_citizen)):
    """Stato del parco: ok, warning o alert. Lo calcola il backend: l'app lo mostra
    così com'è. Non conta mai le situazioni di sicurezza."""
    _active_park(db, park_id)
    return ParkStatus(**svc.park_status(db, park_id))


@router.get("/parks/{park_id}/notices", response_model=list[ParkNoticeOut])
def list_park_notices(park_id: int, db: Session = Depends(get_db), citizen: Citizen = Depends(get_current_citizen)):
    """Avvisi in corso, scritti dagli operatori. Prima i più gravi."""
    _active_park(db, park_id)
    return [
        ParkNoticeOut(id=n.id, title=n.title, body=n.body, level=n.level, starts_at=_utc(n.starts_at),
                      ends_at=_utc(n.ends_at) if n.ends_at else None)
        for n in svc.active_notices(db, park_id)
    ]


_openapi_cache: dict | None = None


@router.get("/openapi.json", include_in_schema=False)
def citizen_openapi(request: Request):
    """Schema OpenAPI con le sole API /citizen, per generare i modelli Dart
    (openapi-generator). Resta attivo anche con ENABLE_DOCS=false."""
    global _openapi_cache
    if _openapi_cache is None:
        # Si filtra lo schema completo (generato anche con ENABLE_DOCS=false): dai path
        # /citizen/ si seguono i $ref per tenere solo gli schemi che servono davvero
        full = copy.deepcopy(request.app.openapi())
        paths = {p: v for p, v in full["paths"].items() if p.startswith("/citizen/")}
        all_schemas = full.get("components", {}).get("schemas", {})
        used, stack = set(), [paths]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                ref = node.get("$ref")
                if isinstance(ref, str) and ref.startswith("#/components/schemas/"):
                    name = ref.rsplit("/", 1)[1]
                    if name not in used:
                        used.add(name)
                        stack.append(all_schemas[name])
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
        schemes = {name for op in (o for v in paths.values() for o in v.values() if isinstance(o, dict))
                   for req in op.get("security", []) for name in req}
        _openapi_cache = {
            "openapi": full["openapi"],
            "info": {
                "title": "Treeyes – API del cittadino", "version": full["info"]["version"],
                "description": "API dell'app del cittadino. Gli aggiornamenti live arrivano da WS /citizen/ws?token=… "
                               "con messaggi {type, data}: report_updated, notice_created, park_status_changed.",
            },
            "paths": paths,
            "components": {
                "schemas": {k: v for k, v in all_schemas.items() if k in used},
                "securitySchemes": {k: v for k, v in full.get("components", {}).get("securitySchemes", {}).items() if k in schemes},
            },
        }
    return _openapi_cache


@router.websocket("/ws")
async def citizen_ws(websocket: WebSocket, token: str | None = Query(None)):
    """Aggiornamenti live: report_updated (solo al proprietario), notice_created e
    park_status_changed (a tutti, con park_id). Token in query (?token=…): il
    WebSocket non ha header custom. Token non valido o cittadino bloccato -> chiusura
    1008. L'app manda "ping" ogni 25 s; il resto di quello che arriva si ignora."""
    db = SessionLocal()
    try:
        citizen = citizen_from_token(token, db)
        citizen_id = citizen.id if citizen is not None and not citizen.blocked else None
    finally:
        db.close()
    if citizen_id is None:
        # accept + close 1008: l'app capisce che deve registrarsi di nuovo, non riprova all'infinito
        await websocket.accept()
        await websocket.close(code=1008)
        return
    await citizen_ws_manager.connect(citizen_id, websocket)
    try:
        while True:
            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
    finally:
        citizen_ws_manager.disconnect(citizen_id, websocket)


@router.get("/categories", response_model=list[CitizenCategoryOut])
def list_categories(db: Session = Depends(get_db), citizen: Citizen = Depends(get_current_citizen)):
    """Categorie delle segnalazioni, con i tipi (problem, suggestion) per cui si possono usare."""
    rows = (
        db.query(CitizenCategory)
        .filter(CitizenCategory.active == True)  # noqa: E712
        .order_by(CitizenCategory.sort_order, CitizenCategory.code)
        .all()
    )
    return [
        CitizenCategoryOut(code=c.code, label=c.label, icon=c.icon, kinds=_kinds(c))
        for c in rows
    ]


# --- Segnalazioni -------------------------------------------------------------

def _kinds(category) -> list[str]:
    return [k.strip() for k in category.kinds.split(",") if k.strip()]


def _invalid(field: str, msg: str):
    """422 nello stesso formato degli errori di validazione di FastAPI (lista dei campi)."""
    return HTTPException(
        422,
        detail=[{"type": "value_error", "loc": ["body", field], "msg": msg}],
    )


_utc = svc.as_utc


def _fmt_created(r) -> ReportCreated:
    return ReportCreated(id=r.id, code=svc.report_code(r), kind=r.kind, status=r.status,
                         status_label=svc.STATUS_LABELS[r.status], created_at=_utc(r.created_at),
                         photo_url=svc.photo_url(r.photo_path))


def _summary_fields(r) -> dict:
    return dict(id=r.id, code=svc.report_code(r), kind=r.kind, category=r.category,
                summary=svc.summary(r.description), status=r.status,
                status_label=svc.STATUS_LABELS[r.status],
                created_at=_utc(r.created_at), updated_at=_utc(r.updated_at or r.created_at))


def _check_report_rate(db: Session, citizen: Citizen) -> None:
    """Al massimo CITIZEN_REPORTS_PER_HOUR segnalazioni nell'ultima ora. Contate sul
    DB, quindi il limite regge anche con più worker o dopo un riavvio."""
    since = datetime.now(timezone.utc) - timedelta(hours=1)
    count, oldest = (
        db.query(func.count(CitizenReport.id), func.min(CitizenReport.created_at))
        .filter(CitizenReport.citizen_id == citizen.id, CitizenReport.created_at >= since)
        .one()
    )
    if count >= settings.CITIZEN_REPORTS_PER_HOUR:
        retry_after = max(1, int((_utc(oldest) - since).total_seconds()) + 1)
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Hai inviato molte segnalazioni nell'ultima ora, riprova più tardi",
            headers={"Retry-After": str(retry_after)},
        )


def _read_photo(photo: UploadFile | None) -> bytes | None:
    if photo is None:
        return None
    data = photo.file.read(svc.PHOTO_MAX_BYTES + 1)
    if not data:
        raise _invalid("photo", "La foto è vuota")
    if len(data) > svc.PHOTO_MAX_BYTES:
        raise _invalid("photo", "La foto supera i 5 MB")
    try:
        return svc.process_photo(data)
    except svc.PhotoError as e:
        raise _invalid("photo", str(e))


@router.post(
    "/reports",
    response_model=ReportCreated,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "client_ref già inviato: si restituisce la segnalazione esistente"}},
)
def create_report(
    response: Response,
    kind: Literal["problem", "suggestion", "feedback"] = Form(...),
    park_id: int = Form(...),
    description: str = Form(..., max_length=1000),
    client_ref: UUID = Form(..., description="UUID creato una volta per segnalazione: uguale nei reinvii"),
    category: str | None = Form(None),
    priority: Literal["low", "medium", "high"] | None = Form(None),
    lat: float | None = Form(None, ge=-90, le=90),
    lon: float | None = Form(None, ge=-180, le=180),
    rating: int | None = Form(None, ge=1, le=5),
    photo: UploadFile | None = File(None, description="JPEG o PNG, max 5 MB"),
    citizen: Citizen = Depends(get_current_citizen),
    db: Session = Depends(get_db),
):
    """Invia un problema, un suggerimento o un feedback. Sempre multipart/form-data,
    anche senza foto. I campi obbligatori dipendono da `kind`."""
    ref = str(client_ref)
    existing = (
        db.query(CitizenReport)
        .filter(CitizenReport.citizen_id == citizen.id, CitizenReport.client_ref == ref)
        .first()
    )
    if existing:
        # Reinvio dopo un errore di rete: niente doppione e nessun consumo del limite
        response.status_code = status.HTTP_200_OK
        return _fmt_created(existing)

    _check_report_rate(db, citizen)

    park = db.query(Park).filter(Park.id == park_id, Park.active == True).first()  # noqa: E712
    if park is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Parco non trovato")

    description = description.strip()
    if len(description) < 10:
        raise _invalid("description", "La descrizione deve avere almeno 10 caratteri")

    if category is not None:
        cat = db.query(CitizenCategory).filter(CitizenCategory.code == category,
                                               CitizenCategory.active == True).first()  # noqa: E712
        if cat is None:
            raise _invalid("category", "Categoria sconosciuta")
        if kind != "feedback" and kind not in _kinds(cat):
            raise _invalid("category", f"La categoria non si può usare per '{kind}'")
    elif kind != "feedback":
        raise _invalid("category", "La categoria è obbligatoria")

    if kind == "problem":
        if lat is None or lon is None:
            raise _invalid("lat" if lat is None else "lon", "La posizione è obbligatoria per un problema")
        priority = priority or "medium"
    else:
        priority = None
    if (lat is None) != (lon is None):
        raise _invalid("lat" if lat is None else "lon", "Servono sia lat sia lon")
    if kind == "feedback":
        if rating is None:
            raise _invalid("rating", "Il voto (da 1 a 5) è obbligatorio per un feedback")
        if photo is not None:
            raise _invalid("photo", "Il feedback non prevede una foto")
    else:
        rating = None

    if lat is not None and park.lat is not None and park.lon is not None:
        radius = park.radius_m or settings.CITIZEN_PARK_RADIUS_M
        if _hav(lat, lon, park.lat, park.lon) > radius:
            raise _invalid("lat", "La posizione indicata è fuori dal parco")

    jpeg = _read_photo(photo)

    now = datetime.now(timezone.utc)
    report = CitizenReport(
        citizen_id=citizen.id, park_id=park.id, kind=kind, category=category,
        description=description, priority=priority, lat=lat, lon=lon, rating=rating,
        client_ref=ref, status="received", created_at=now, updated_at=now,
    )
    report.history.append(CitizenReportHistory(status="received", at=now))
    # Prima il file e poi la riga: se il commit fallisce il file si toglie,
    # così non restano né righe senza file né file senza riga
    report.photo_path = svc.save_photo(jpeg) if jpeg else None
    db.add(report)
    try:
        db.commit()
    except IntegrityError:
        # Stesso client_ref inviato due volte in contemporanea: vince il primo
        db.rollback()
        svc.delete_photo(report.photo_path)
        existing = (
            db.query(CitizenReport)
            .filter(CitizenReport.citizen_id == citizen.id, CitizenReport.client_ref == ref)
            .first()
        )
        if existing is None:
            raise
        response.status_code = status.HTTP_200_OK
        return _fmt_created(existing)
    except Exception:
        db.rollback()
        svc.delete_photo(report.photo_path)
        raise
    if kind == "problem":
        # Suggerimenti e feedback non diventano eventi né pratiche
        svc.correlate_report(db, report)
    db.refresh(report)
    return _fmt_created(report)




# --- Idee della comunità ------------------------------------------------------

def _idea_fields(r, db: Session, citizen_id: int) -> dict:
    votes = db.query(func.count(CitizenIdeaVote.id)).filter(
        CitizenIdeaVote.idea_id == r.id
    ).scalar() or 0
    voted = db.query(CitizenIdeaVote.id).filter(
        CitizenIdeaVote.idea_id == r.id,
        CitizenIdeaVote.citizen_id == citizen_id,
    ).first() is not None
    return {
        "id": r.id,
        "code": svc.report_code(r),
        "title": r.title or "Idea",
        "description": r.description,
        "visibility": r.visibility,
        "vote_count": votes,
        "voted_by_me": voted,
        "created_at": _utc(r.created_at),
    }


def _public_idea_or_404(db: Session, idea_id: int) -> CitizenReport:
    idea = db.query(CitizenReport).filter(
        CitizenReport.id == idea_id,
        CitizenReport.kind == "suggestion",
        CitizenReport.visibility == "public",
    ).first()
    if idea is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Idea non trovata")
    return idea


@router.get("/ideas", response_model=IdeaPage)
def list_ideas(
    park_id: int | None = Query(None, ge=1),
    sort: Literal["recent", "votes"] = Query("recent"),
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=50),
    citizen: Citizen = Depends(get_current_citizen),
    db: Session = Depends(get_db),
):
    """Idee pubbliche della comunità. Le idee private sono visibili solo agli operatori."""
    q = db.query(CitizenReport).filter(
        CitizenReport.kind == "suggestion",
        CitizenReport.visibility == "public",
    )
    if park_id is not None:
        _active_park(db, park_id)
        q = q.filter(CitizenReport.park_id == park_id)
    total = q.count()
    if sort == "votes":
        vote_counts = (
            db.query(CitizenIdeaVote.idea_id, func.count(CitizenIdeaVote.id).label("votes"))
            .group_by(CitizenIdeaVote.idea_id)
            .subquery()
        )
        rows = (
            q.outerjoin(vote_counts, CitizenReport.id == vote_counts.c.idea_id)
            .order_by(func.coalesce(vote_counts.c.votes, 0).desc(),
                      CitizenReport.created_at.desc(), CitizenReport.id.desc())
            .offset(skip).limit(limit).all()
        )
    else:
        rows = q.order_by(CitizenReport.created_at.desc(), CitizenReport.id.desc()).offset(skip).limit(limit).all()
    return IdeaPage(items=[IdeaOut(**_idea_fields(r, db, citizen.id)) for r in rows], total=total)


@router.post(
    "/ideas",
    response_model=IdeaOut,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "client_ref già inviato: si restituisce l'idea esistente"}},
)
def create_idea(
    body: IdeaCreate,
    response: Response,
    citizen: Citizen = Depends(get_current_citizen),
    db: Session = Depends(get_db),
):
    """Crea un suggerimento con titolo e visibilità. Le idee private non appaiono nella comunità."""
    ref = str(body.client_ref)
    existing = db.query(CitizenReport).filter(
        CitizenReport.citizen_id == citizen.id,
        CitizenReport.client_ref == ref,
    ).first()
    if existing is not None:
        if existing.kind != "suggestion" or not existing.title:
            raise HTTPException(status.HTTP_409_CONFLICT, "client_ref già utilizzato per un'altra segnalazione")
        response.status_code = status.HTTP_200_OK
        return IdeaOut(**_idea_fields(existing, db, citizen.id))

    _check_report_rate(db, citizen)
    park = db.query(Park).filter(Park.id == body.park_id, Park.active == True).first()  # noqa: E712
    if park is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Parco non trovato")

    title = body.title.strip()
    description = body.description.strip()
    if len(title) < 3:
        raise _invalid("title", "Il titolo deve contenere almeno 3 caratteri")
    if len(description) < 10:
        raise _invalid("description", "La descrizione deve contenere almeno 10 caratteri")

    now = datetime.now(timezone.utc)
    idea = CitizenReport(
        citizen_id=citizen.id,
        park_id=park.id,
        kind="suggestion",
        category=None,
        title=title,
        visibility=body.visibility,
        description=description,
        priority=None,
        lat=None,
        lon=None,
        rating=None,
        client_ref=ref,
        status="received",
        created_at=now,
        updated_at=now,
    )
    idea.history.append(CitizenReportHistory(status="received", at=now))
    db.add(idea)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        existing = db.query(CitizenReport).filter(
            CitizenReport.citizen_id == citizen.id,
            CitizenReport.client_ref == ref,
        ).first()
        if existing is None:
            raise
        if existing.kind != "suggestion" or not existing.title:
            raise HTTPException(status.HTTP_409_CONFLICT, "client_ref già utilizzato per un'altra segnalazione")
        response.status_code = status.HTTP_200_OK
        return IdeaOut(**_idea_fields(existing, db, citizen.id))
    db.refresh(idea)
    return IdeaOut(**_idea_fields(idea, db, citizen.id))


@router.post("/ideas/{idea_id}/vote", response_model=IdeaVoteResult)
def vote_idea(
    idea_id: int,
    citizen: Citizen = Depends(get_current_citizen),
    db: Session = Depends(get_db),
):
    """Aggiunge un voto; il vincolo univoco impedisce voti duplicati."""
    idea = _public_idea_or_404(db, idea_id)
    vote = db.query(CitizenIdeaVote).filter(
        CitizenIdeaVote.idea_id == idea.id,
        CitizenIdeaVote.citizen_id == citizen.id,
    ).first()
    if vote is None:
        db.add(CitizenIdeaVote(idea_id=idea.id, citizen_id=citizen.id))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()  # un'altra richiesta dello stesso cittadino ha già votato
    count = db.query(func.count(CitizenIdeaVote.id)).filter(CitizenIdeaVote.idea_id == idea.id).scalar() or 0
    return IdeaVoteResult(idea_id=idea.id, vote_count=count, voted_by_me=True)


@router.delete("/ideas/{idea_id}/vote", response_model=IdeaVoteResult)
def remove_idea_vote(
    idea_id: int,
    citizen: Citizen = Depends(get_current_citizen),
    db: Session = Depends(get_db),
):
    """Rimuove il voto del cittadino autenticato, se presente."""
    idea = _public_idea_or_404(db, idea_id)
    vote = db.query(CitizenIdeaVote).filter(
        CitizenIdeaVote.idea_id == idea.id,
        CitizenIdeaVote.citizen_id == citizen.id,
    ).first()
    if vote is not None:
        db.delete(vote)
        db.commit()
    count = db.query(func.count(CitizenIdeaVote.id)).filter(CitizenIdeaVote.idea_id == idea.id).scalar() or 0
    return IdeaVoteResult(idea_id=idea.id, vote_count=count, voted_by_me=False)


@router.get("/reports", response_model=ReportPage)
def list_reports(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=50),
    kind: Literal["problem", "suggestion", "feedback"] | None = Query(None),
    citizen: Citizen = Depends(get_current_citizen),
    db: Session = Depends(get_db),
):
    """Le segnalazioni del cittadino, dalla più recente."""
    q = db.query(CitizenReport).filter(CitizenReport.citizen_id == citizen.id)
    if kind is not None:
        q = q.filter(CitizenReport.kind == kind)
    total = q.count()
    rows = q.order_by(CitizenReport.created_at.desc(), CitizenReport.id.desc()).offset(skip).limit(limit).all()
    return ReportPage(items=[ReportSummary(**_summary_fields(r)) for r in rows], total=total)


@router.get("/reports/{report_id}", response_model=ReportDetail)
def get_report(
    report_id: int,
    citizen: Citizen = Depends(get_current_citizen),
    db: Session = Depends(get_db),
):
    """Dettaglio e storico degli stati. Le segnalazioni di altri cittadini rispondono
    404, come quelle inesistenti: non se ne rivela l'esistenza."""
    r = (
        db.query(CitizenReport)
        .options(selectinload(CitizenReport.history))
        .filter(CitizenReport.id == report_id, CitizenReport.citizen_id == citizen.id)
        .first()
    )
    if r is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Segnalazione non trovata")
    return ReportDetail(
        **_summary_fields(r),
        description=r.description, priority=r.priority, lat=r.lat, lon=r.lon,
        rating=r.rating, photo_url=svc.photo_url(r.photo_path),
        history=[ReportHistoryItem(status=h.status, at=_utc(h.at), note=h.note) for h in r.history],
    )
