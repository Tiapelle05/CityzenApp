from typing import List
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session, joinedload

from app.api.dependencies import get_db, get_current_user
from app.db.models import Event, EventVideo, AppUser, TypeEvent
from app.schemas.event import Event as EventSchema
from app.core.config import settings

router = APIRouter()


@router.get("/", response_model=List[EventSchema])
def read_user_events(
    skip: int = 0,
    limit: int = 100,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Eventi filtrati in base al ruolo utente:
    - admin: tutti gli eventi, senza dati video
    - op_eco: tutti gli eventi tranne gli alert
    - ente: solo eventi alert, con dati video
    """
    # Le segnalazioni dei cittadini si vedono dentro le pratiche, con le regole di
    # visibilità per categoria: qui op_eco vedrebbe anche quelle di sicurezza
    query = db.query(Event).options(joinedload(Event.video)).filter(Event.type != TypeEvent.citizen)

    if current_user.type == "op_eco":
        query = query.filter(Event.type != "alert")
    elif current_user.type == "ente":
        query = query.filter(Event.type == "alert")
    elif current_user.type != "admin":
        query = query.filter(Event.id == -1)

    events = query.order_by(Event.transmission_time.desc()).offset(skip).limit(limit).all()

    if current_user.type == "admin":
        for event in events:
            event.video = None

    return events


@router.get("/videos")
def get_video_events(
    request: Request,
    skip: int = 0,
    limit: int = 50,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Eventi con video associato, riservato agli utenti 'ente'."""
    if current_user.type != "ente":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Solo utenti ente possono accedere ai video")

    events = (
        db.query(Event)
        .join(EventVideo, Event.id == EventVideo.id_event)
        .options(joinedload(Event.video))
        .filter(Event.type == "alert")
        .order_by(Event.transmission_time.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )

    base_url = settings.BASE_URL.rstrip("/")
    result = []
    for event in events:
        video_data = None
        if event.video:
            video_url = event.video.video_url
            if video_url.startswith("/"):
                video_url = f"{base_url}{video_url}"

            thumbnail_url = event.video.thumbnail_url
            if thumbnail_url and thumbnail_url.startswith("/"):
                thumbnail_url = f"{base_url}{thumbnail_url}"

            video_data = {
                "id": event.video.id,
                "video_url": video_url,
                "thumbnail_url": thumbnail_url,
                "duration_seconds": event.video.duration_seconds,
                "created_at": event.video.created_at,
            }

        result.append({
            "event_id": event.id,
            "mac_address": event.mac_address,
            "type": event.type,
            "sampling_time": event.sampling_time,
            "transmission_time": event.transmission_time,
            "video": video_data,
        })

    return result
