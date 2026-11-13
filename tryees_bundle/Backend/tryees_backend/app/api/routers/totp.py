import pyotp
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.api.dependencies import get_db, get_current_user
from app.db.models import AppUser, AccessLog

router = APIRouter()


class VerifyBody(BaseModel):
    code: str


class DisableBody(BaseModel):
    code: str


@router.post("/setup")
def setup_totp(
    request: Request,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    secret = pyotp.random_base32()
    current_user.totp_secret = secret
    current_user.totp_enabled = False
    db.commit()

    totp = pyotp.TOTP(secret)
    uri  = totp.provisioning_uri(name=current_user.username, issuer_name="Treeyes")

    return {
        "secret": secret,
        "otpauth_uri": uri,
        "instructions": "Scansiona il QR con Google Authenticator o Authy, poi conferma con /auth/2fa/confirm",
    }


@router.post("/confirm")
def confirm_totp(
    body: VerifyBody,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    if not current_user.totp_secret:
        raise HTTPException(400, "2FA non inizializzata — chiama /auth/2fa/setup prima")

    totp = pyotp.TOTP(current_user.totp_secret)
    if not totp.verify(body.code, valid_window=1):
        raise HTTPException(400, "Codice non valido")

    current_user.totp_enabled = True
    db.add(AccessLog(user_id=current_user.id, username=current_user.username, action="2fa_enabled", ip=_ip(request)))
    db.commit()
    return {"ok": True, "message": "2FA attivata con successo"}


@router.post("/verify")
def verify_totp(
    body: VerifyBody,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    if not current_user.totp_enabled or not current_user.totp_secret:
        raise HTTPException(400, "2FA non attivata")

    totp = pyotp.TOTP(current_user.totp_secret)
    if not totp.verify(body.code, valid_window=1):
        db.add(AccessLog(user_id=current_user.id, username=current_user.username, action="2fa_failed", ip=_ip(request), success=False))
        db.commit()
        raise HTTPException(401, "Codice non valido")

    db.add(AccessLog(user_id=current_user.id, username=current_user.username, action="2fa_verified", ip=_ip(request)))
    db.commit()
    return {"ok": True}


@router.post("/disable")
def disable_totp(
    body: DisableBody,
    request: Request,
    db: Session = Depends(get_db),
    current_user: AppUser = Depends(get_current_user),
):
    if not current_user.totp_enabled:
        raise HTTPException(400, "2FA non attivata")

    totp = pyotp.TOTP(current_user.totp_secret)
    if not totp.verify(body.code, valid_window=1):
        raise HTTPException(401, "Codice non valido")

    current_user.totp_enabled = False
    current_user.totp_secret  = None
    db.add(AccessLog(user_id=current_user.id, username=current_user.username, action="2fa_disabled", ip=_ip(request)))
    db.commit()
    return {"ok": True}


@router.get("/status")
def totp_status(current_user: AppUser = Depends(get_current_user)):
    return {"enabled": bool(current_user.totp_enabled), "username": current_user.username}


def _ip(request: Request) -> str:
    forwarded = request.headers.get("X-Forwarded-For")
    return forwarded.split(",")[0] if forwarded else (request.client.host if request.client else "unknown")
