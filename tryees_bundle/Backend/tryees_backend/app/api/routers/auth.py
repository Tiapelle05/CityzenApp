from datetime import datetime, timedelta, timezone
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.core.security import verify_password, create_access_token
from app.core.config import settings
from app.api.dependencies import get_db, get_current_user
from app.db.models import AppUser, AccessLog
from app.schemas.token import Token
from app.schemas.user import User

router = APIRouter()


def _ip(request: Request) -> str:
    forwarded = request.headers.get("X-Forwarded-For")
    return forwarded.split(",")[0].strip() if forwarded else (request.client.host if request.client else "unknown")


@router.post("/login/access-token-2", response_model=Token)
def login_access_token(
    request: Request,
    db: Session = Depends(get_db),
    form_data: OAuth2PasswordRequestForm = Depends(),
) -> Any:
    """
    OAuth2 compatible token login, ottiene e restituisce un access token per richieste API future.
    """
    user = db.query(AppUser).filter(AppUser.username == form_data.username).first()
    if not user or not verify_password(form_data.password, user.password):
        db.add(AccessLog(
            user_id=user.id if user else None,
            username=form_data.username,
            action="login_failed",
            ip=_ip(request),
            success=False,
        ))
        if user:
            user.failed_logins = (user.failed_logins or 0) + 1
        db.commit()
        raise HTTPException(status_code=400, detail="Username o password errati")

    user.last_login = datetime.now(timezone.utc)
    user.failed_logins = 0
    db.add(AccessLog(
        user_id=user.id,
        username=user.username,
        action="login_success",
        ip=_ip(request),
        success=True,
    ))
    db.commit()

    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return {
        "access_token": create_access_token(
            data={"sub": user.username}, expires_delta=access_token_expires
        ),
        "token_type": "bearer",
    }

@router.get("/me", response_model=User)
def read_user_me(current_user: AppUser = Depends(get_current_user)) -> Any:
    """
    Restituisce i dati dell'utente attualmente loggato.
    Utile per il frontend per verificare il ruolo (admin, op_eco, ecc.)
    """
    return current_user
