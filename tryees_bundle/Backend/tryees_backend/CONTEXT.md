# Contesto progetto — Treeyes / backend_evolved

> Documento di contesto generato per orientarsi rapidamente nel codebase.
> Ultimo aggiornamento: 2026-10-28.

## 1. Cos'è

Backend IoT per il monitoraggio di parchi urbani ("smart city / smart park").
Raccoglie dati da dispositivi ESP32/Raspberry (telecamere IA, microfoni, cestini,
luci, sensori suolo, nodi "modellino/digital twin"), li correla in **pratiche**
(incidenti/interventi), attiva **attuatori** (sirene, LED polizia, luci) via MQTT,
e notifica gli operatori via WebSocket, dashboard e bot Telegram.

Stack: **FastAPI** (Python), **SQLAlchemy 2** + **Alembic**, **PostgreSQL**
(fallback SQLite), **MQTT** (paho/Mosquitto), **FFmpeg** per transcodifica video,
frontend **React/Vite** (`webapp/`).

## 2. Struttura

```
app/
  main.py                 # app FastAPI, lifespan (MQTT+Telegram+seed), CORS, router mount
  core/
    config.py             # Settings (pydantic-settings), .env -> DATABASE_URL, UPLOAD_DIR
    security.py           # bcrypt hash/verify, JWT create (HS256)
    mqtt.py               # MQTTClientManager: ingest eventi, arricchimento, automazioni, comandi attuatori
    telegram.py           # Bot Telegram: login per ruolo, notifiche, comandi (/stato, /cestini...)
    ws_manager.py         # ConnectionManager WebSocket, broadcast_from_thread
  db/
    database.py           # engine, SessionLocal, Base; fallback Postgres->SQLite
    models.py             # tutti i modelli ORM
    init_defaults.py      # seed utenti/parco demo all'avvio (nessun device)
  api/
    dependencies.py       # get_db, get_current_user (JWT), get_current_device/camera (X-MAC-Address)
    routers/
      auth.py             # POST /auth/login/access-token, GET /auth/me
      totp.py             # /auth/2fa/setup|confirm|verify|disable|status (pyotp)
      events.py           # GET /events (per ruolo), /events/videos (ente)
      practices.py        # CRUD pratiche, WS /practices/ws, audit, escalate, archive
      devices_v2.py       # elenco/stato/manutenzione/delete device
      onboarding.py       # registrazione device + API key (solo admin)
      parks.py            # CRUD parchi
      sla.py              # /sla health di sistema, access-log
      server_monitor.py   # /sla/server: CPU, memoria, disco, retention video (solo admin)
      vision.py           # upload snapshot/clip da nodo camera (FFmpeg H264)
      mini_dashboard.py   # dashboard modellino: /mini/* (state, stream SSE, alarms, settings, test-trigger)
      power.py            # consumi elettrici (EventPower): latest/history/daily
  schemas/                # Pydantic: token, user, event
  services/
    correlation.py        # CorrelationEngine: raggruppa eventi in pratiche per zona/tempo/categoria
    retention.py          # elimina le clip video più vecchie di VIDEO_RETENTION_MINUTES
    server_monitor.py     # campiona CPU/memoria/disco (psutil) per la scheda "Server"
alembic/                  # migrazioni
scripts/                  # create_admin.py, seed_demo_users.py, transcode_existing_videos.py
webapp/                   # frontend React (dashboard per ruolo)
docker-compose.yml        # db (postgres15) + mosquitto + backend + dashboard(nginx)
```

## 3. Modello dati (models.py)

- **AppUser**: username, password (bcrypt), `type` (admin/op_eco/ente), park_id,
  campi 2FA (totp_secret/totp_enabled), `failed_logins`, `locked_until`, `last_login`.
- **Device**: PK = `mac_address`, type (camera/microphone/light/basket/soil_sensor +
  nodi mini_* + server), zona, lat/lon, status, last_seen, buzzer_active.
- **Event**: mac_address, type (Enum TypeEvent), val_number, sampling/transmission_time.
  Tabelle di dettaglio polimorfe: EventCamera, EventMicrophone, EventBasket,
  EventLight, EventSoil, EventPower (1:1 via event_id).
- **Practice**: incidente correlato (status open/in_progress/resolved/closed, severity,
  category security/basket/soil/other, lat/lon/zone). M:N con Event via `practice_event`.
- **PracticeAudit / MaintenanceLog / AccessLog / CommandLog**: audit/log.
- **EventAlarm**: allarmi modellino (sirena/LED polizia, riarmabile).
- **EventVideo / MiniVideoLog**: clip reali e video mock del modellino.
- **TelegramSession**: chat_id -> user/role per instradare notifiche bot.
- **ApiKey**: chiavi device (generate all'onboarding) — *definite ma non usate per auth*.
- **Park / Setting**: parchi e soglie configurabili (vandal_tilt, bin_full_pct...).

## 4. Autenticazione & ruoli

- **Utenti**: OAuth2 password flow -> JWT HS256 (`sub`=username, exp 30 min).
  `get_current_user` decodifica il token e carica l'utente.
- **Device**: header `X-MAC-Address` -> `get_current_device` cerca il device.
  `get_current_camera` aggiunge il vincolo type==camera. **Nessun segreto/API key.**
- **Ruoli** (visibilità dati):
  - `admin`: tutto.
  - `ente` (frontend "polizia"): eventi/pratiche `alert`/security + video.
  - `op_eco` (frontend "eco"/"manutenzione"): eventi non-alert, pratiche `basket`.
- **2FA (TOTP)**: endpoint setup/confirm/verify presenti, **ma non applicata al login**.

## 5. Pipeline eventi (mqtt.py)

1. Backend subscribe a `parco/#`. `on_message` parsa JSON.
2. Gestione stato offline (LWT/`status:offline`).
3. Identifica device (payload `device_id`/`mac_address` o topic); aggiorna last_seen.
   Se il device è una camera e il messaggio è una presenza (`type: presence` o topic
   `parco/<id>/presence`): accende solo le luci della sua zona e si ferma qui
   (nessun Event/pratica/WebSocket: non compare in webapp).
4. `_save_events`: formato a campo singolo (`type`+`val_number`) o multi-campo
   (motion/alert/full/battery/humidity/light/ingresso/uscita/power_w).
5. `_enrich`: crea la riga di dettaglio polimorfa in base a tipo device/evento;
   attiva broadcast allarme al modellino (camera alert) o luci di zona (camera motion).
6. `_automations`: soglie (vandalismo cestino, cestino pieno, presenza luci, affollamento)
   -> pubblica comandi su topic attuatori `smartcity/actuators/*`.
7. `_correlate` -> `CorrelationEngine.process_event`: aggancia l'evento a una pratica
   esistente vicina (≤50 m, ≤15 min, stessa categoria) o ne crea una nuova; poi
   broadcast WebSocket + notifica Telegram.

## 6. Config / deploy

- `.env` (non versionato) con SECRET_KEY, credenziali Postgres/MQTT, TELEGRAM_BOT_TOKEN.
- `database.py` prova Postgres; se irraggiungibile fa **fallback silenzioso a SQLite**
  (`treeyes.db`).
- All'avvio `seed_default_data` crea/**ripristina** utenti demo (password `admin123`),
  parco "Parco Robinson"; i device non vengono più creati all'avvio.
- Docker: postgres + mosquitto + backend (uvicorn) + dashboard nginx.
- Retention video: le clip in `uploads/videos` (file, thumbnail, riga `event_video`) vengono
  eliminate dopo `VIDEO_RETENTION_MINUTES` (default 60, 0 = mai), controllo ogni
  `VIDEO_CLEANUP_INTERVAL_SECONDS`. `mock_videos` non viene toccato.
- Retention pratiche: quelle con dati di telecamere o microfoni dopo `PRACTICE_RETENTION_HOURS`
  (default 48, 0 = mai), le altre (cestini, suolo, cittadini) dopo
  `PRACTICE_RETENTION_DAYS_NON_SECURITY` giorni (default 30); sempre con i loro eventi, in
  qualunque stato. Con il termine delle 48 ore (data del file) si eliminano gli snapshot in
  `uploads/snapshots`, come da informativa privacy.
- Retention cittadini: segnalazioni risolte/chiuse dopo `CITIZEN_REPORT_RETENTION_DAYS`
  (default 30) con storico e foto; installazioni senza segnalazioni inattive da
  `CITIZEN_INACTIVE_DAYS` (default 365).
- `ENABLE_DOCS=false` spegne `/docs`, `/redoc` e `/openapi.json`.

## 6bis. Citizen App (`/citizen`)

Design completo, decisioni e piano in `CITIZEN_API_DESIGN.md`. In breve:

- `routers/citizen.py`: API dell'app Flutter. Installazione anonima (`POST /register`,
  token JWT con `scope: "citizen"` che le API operatori rifiutano), parchi, categorie,
  segnalazioni con foto (`/reports`), stato del parco e avvisi, WebSocket `/citizen/ws`,
  schema `/citizen/openapi.json` con le sole API del cittadino.
- Un **problema** diventa un evento `citizen` (senza device, dettaglio in `event_citizen`)
  che entra nella correlazione: zona dal device più vicino, finestra di 24 ore, merge solo
  con eventi sensore compatibili (`citizen_category.merge_types`). Suggerimenti e feedback
  restano solo in `citizen_report`.
- Lo stato della segnalazione segue la pratica (`services/citizen.py: sync_reports`), con
  storico e `citizen_note` visibile al cittadino; sopravvive alla cancellazione della pratica.
- Stato del parco: mai dati di sicurezza; `alert` solo da un avviso (`park_notice`) scritto
  da un operatore. `park_watch_loop` ogni 30 s annuncia i cambi ai cittadini connessi.
- Operatori: avvisi su `/parks/{id}/notices`, suggerimenti e feedback su `/citizen-reports`
  (admin); in dashboard le sezioni "Avvisi" e "Suggerimenti" e la nota per i cittadini nel
  dettaglio pratica.

## 7. Convenzioni

- Codice e commenti in **italiano**.
- Router montati con prefissi in `main.py`; ogni router usa `Depends(get_db)` +
  `get_current_user` (tranne alcuni endpoint `/mini/*` — vedi review).
- Enum SQLAlchemy con valori lowercase; confronti spesso con `.value`.
- Notifiche live: WebSocket (`/practices/ws?token=`) + SSE (`/mini/stream`); per i
  cittadini un WebSocket separato (`/citizen/ws?token=`, `core/citizen_ws.py`).

## 8. Punti di attenzione noti

Vedi `SECURITY_REVIEW.md` per l'elenco completo di problemi/vulnerabilità/bug
individuati nella review del 2026-09-30 (auth device via LIKE, 2FA non applicata,
endpoint `/mini/*` senza auth, SECRET_KEY debole, seed che resetta le password, ecc.).
