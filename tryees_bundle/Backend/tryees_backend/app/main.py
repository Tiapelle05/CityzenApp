import asyncio, os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.mqtt import mqtt_manager
from app.core.ws_manager import ws_manager
from app.core.citizen_ws import citizen_ws_manager
from app.core.telegram import telegram_bot
from app.api.routers import auth, events
from app.api.routers import practices, devices_v2, parks, onboarding, totp, sla, vision, mini_dashboard, power, server_monitor, citizen, citizen_ops
from app.services.retention import retention_loop
from app.services.server_monitor import sampler_loop
from app.services.citizen import park_watch_loop

os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
os.makedirs(settings.VIDEOS_DIR, exist_ok=True)
os.makedirs(os.path.join(settings.UPLOAD_DIR, "mock_videos"), exist_ok=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    ws_manager.set_loop(asyncio.get_event_loop())
    citizen_ws_manager.set_loop(asyncio.get_event_loop())
    mqtt_manager.start()
    telegram_bot.start()
    try:
        from app.db.database import SessionLocal
        from app.db.init_defaults import seed_default_data
        with SessionLocal() as db:
            seed_default_data(db)
    except Exception as e:
        import logging
        logging.getLogger(__name__).warning(f"Default data seeding failed: {e}")
    background = [asyncio.create_task(retention_loop()), asyncio.create_task(sampler_loop()),
                  asyncio.create_task(park_watch_loop())]
    yield
    for task in background:
        task.cancel()
    mqtt_manager.stop()
    telegram_bot.stop()


# ENABLE_DOCS=false spegne Swagger (che elenca anche le API operatori); /citizen/openapi.json resta
app = FastAPI(
    title="Treeyes API", version="2.0.0", lifespan=lifespan,
    docs_url="/docs" if settings.ENABLE_DOCS else None,
    redoc_url="/redoc" if settings.ENABLE_DOCS else None,
    openapi_url="/openapi.json" if settings.ENABLE_DOCS else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/xx", tags=["health"])
def health():
    return {"status": "ok", "version": "2.0.0"}


app.include_router(auth.router,       prefix="/auth",       tags=["auth"])
app.include_router(totp.router,       prefix="/auth/2fa",   tags=["2fa"])
app.include_router(events.router,     prefix="/events",     tags=["events"])
app.include_router(practices.router,  prefix="/practices",  tags=["practices"])
app.include_router(devices_v2.router, prefix="/devices",    tags=["devices"])
app.include_router(parks.router,      prefix="/parks",      tags=["parks"])
app.include_router(onboarding.router, prefix="/onboarding", tags=["onboarding"])
app.include_router(server_monitor.router, prefix="/sla/server", tags=["sla"])
app.include_router(sla.router,        prefix="/sla",        tags=["sla"])
app.include_router(vision.router,     prefix="/api/vision", tags=["vision"])
app.include_router(mini_dashboard.router, prefix="/mini",   tags=["mini-dashboard"])
app.include_router(power.router,      prefix="/power",      tags=["power"])
app.include_router(citizen.router,    prefix="/citizen",    tags=["citizen"])
app.include_router(citizen_ops.router, prefix="/citizen-reports", tags=["citizen-reports"])

try:
    app.mount("/static", StaticFiles(directory=settings.UPLOAD_DIR), name="static")
except Exception:
    pass
