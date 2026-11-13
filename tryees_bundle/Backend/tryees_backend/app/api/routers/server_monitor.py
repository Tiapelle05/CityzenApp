"""
Stato del server per la dashboard Admin (solo amministratori).

  GET  /sla/server          -> CPU, memoria, disco, cartelle di upload e stato della retention video
  POST /sla/server/cleanup  -> elimina subito le clip scadute, senza aspettare il giro automatico
"""

import logging

from fastapi import APIRouter, Depends, HTTPException

from app.api.dependencies import get_current_user
from app.db.models import AppUser
from app.services import retention
from app.services.server_monitor import snapshot

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("")
def server_status(current_user: AppUser = Depends(get_current_user)):
    if current_user.type.value != 'admin':
        raise HTTPException(403, "Solo admin")
    return snapshot()


@router.post("/cleanup")
def run_cleanup(current_user: AppUser = Depends(get_current_user)):
    if current_user.type.value != 'admin':
        raise HTTPException(403, "Solo admin")
    if not retention.is_enabled():
        raise HTTPException(409, "La cancellazione automatica dei video è disattivata (VIDEO_RETENTION_MINUTES=0).")
    result = retention.cleanup_old_videos()
    logger.info(f"[Retention] pulizia manuale: {result['deleted_files']} file eliminati (admin: {current_user.username})")
    return result
