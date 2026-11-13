from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status, Header
from fastapi.security import OAuth2PasswordBearer, HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from jose import jwt, JWTError
from app.db.database import SessionLocal
from app.db.models import Device, AppUser, TypeDevice, Citizen
from app.core.security import ALGORITHM, CITIZEN_SCOPE
from app.core.config import settings

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login/access-token")

def user_from_token(token: str, db: Session):
    """Restituisce l'utente del JWT, o None se il token è assente/non valido/scaduto."""
    if not token:
        return None
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
    if payload.get("scope") == CITIZEN_SCOPE:
        # I token dell'app del cittadino non valgono mai per le API operatori
        return None
    username = payload.get("sub")
    if username is None:
        return None
    return db.query(AppUser).filter(AppUser.username == username).first()


def get_current_user(
    db: Session = Depends(get_db),
    token: str = Depends(oauth2_scheme)
) -> AppUser:
    user = user_from_token(token, db)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessione non valida o scaduta",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user

# auto_error=False: senza header rispondiamo 401 (HTTPBearer di suo può dare 403)
citizen_bearer = HTTPBearer(auto_error=False, description="Token ottenuto da POST /citizen/register")

# last_seen_at si aggiorna al massimo una volta ogni tanto, non a ogni richiesta
CITIZEN_SEEN_EVERY = timedelta(minutes=5)


def citizen_from_token(token: str, db: Session):
    """Restituisce il cittadino del token, o None se assente/non valido/scaduto o non di scope citizen."""
    if not token:
        return None
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
    sub = payload.get("sub") or ""
    if payload.get("scope") != CITIZEN_SCOPE or not sub.startswith("citizen:"):
        return None
    return db.query(Citizen).filter(Citizen.public_id == sub.removeprefix("citizen:")).first()


def get_current_citizen(
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials | None = Depends(citizen_bearer),
) -> Citizen:
    citizen = citizen_from_token(credentials.credentials if credentials else None, db)
    if citizen is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token non valido o scaduto: ripetere la registrazione",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if citizen.blocked:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Questa installazione è stata bloccata")
    now = datetime.now(timezone.utc)
    seen = citizen.last_seen_at
    if seen is not None and seen.tzinfo is None:
        seen = seen.replace(tzinfo=timezone.utc)  # SQLite restituisce date senza fuso
    if seen is None or now - seen > CITIZEN_SEEN_EVERY:
        citizen.last_seen_at = now
        db.commit()
    return citizen


def get_current_device(
    x_mac_address: str = Header(..., alias="X-MAC-Address", description="Il MAC address del dispositivo"),
    db: Session = Depends(get_db)
) -> Device:
    """
    Autentica qualsiasi dispositivo (camera, light, basket, microphone)
    tramite il MAC address nell'header X-MAC-Address.
    """
    device = db.query(Device).filter(Device.mac_address.ilike(x_mac_address.strip())).first()
    
    if not device:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Dispositivo non trovato"
        )
    device.last_seen = datetime.now(timezone.utc)
    db.commit()
    return device


def get_current_camera(
    x_mac_address: str = Header(..., alias="X-MAC-Address", description="Il MAC address della telecamera"),
    db: Session = Depends(get_db)
) -> Device:
    """
    Dipendenza specializzata: autentica solo dispositivi di tipo 'camera'.
    Usa get_current_device internamente e aggiunge il controllo sul tipo.
    """
    device = get_current_device(
        x_mac_address=x_mac_address,
        db=db
    )

    if device.type != TypeDevice.camera:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Il dispositivo non è autorizzato come telecamera"
        )

    return device
