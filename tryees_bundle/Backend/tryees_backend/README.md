# Treeyes — Backend

Backend FastAPI del sistema Treeyes: riceve dati dai sensori del parco
(telecamera IA, ESP32 reali e nodi del modellino) via MQTT, li trasforma
in "pratiche" (incidenti/segnalazioni) e li espone alla dashboard web
via REST + WebSocket.

## Struttura del progetto

```
backend_evolved/
├── app/
│   ├── main.py              # entrypoint FastAPI, monta tutte le route
│   ├── core/
│   │   ├── config.py         # variabili d'ambiente (.env)
│   │   ├── mqtt.py           # client MQTT: riceve i sensori, crea eventi,
│   │   │                     #   logica di automazione (sirena/LED/luci)
│   │   ├── security.py       # hash password, chiavi API
│   │   └── ws_manager.py     # WebSocket verso la dashboard (live update)
│   ├── db/
│   │   ├── database.py       # connessione SQLAlchemy
│   │   └── models.py         # TUTTE le tabelle — vedi nota sotto
│   ├── api/routers/          # un file per gruppo di endpoint:
│   │   ├── auth.py, totp.py      → login, 2FA
│   │   ├── practices.py          → CRUD pratiche/incidenti (usato dalla dashboard)
│   │   ├── devices_v2.py         → CRUD device (Admin → Onboarding)
│   │   ├── onboarding.py         → registrazione device + API key
│   │   ├── parks.py              → gestione multi-parco
│   │   ├── events.py             → ingestione eventi via HTTP (alternativa a MQTT)
│   │   ├── vision.py             → upload snapshot/clip dalla telecamera IA
│   │   ├── mini_dashboard.py     → pannello /mini per il modellino (allarmi, video)
│   │   ├── sla.py                → metriche/health per la dashboard Admin
│   │   └── server_monitor.py     → stato del server (CPU, memoria, disco) e pulizia delle clip
│   └── services/
│       ├── correlation.py    # trasforma un evento in una pratica
│       │                     #   (raggruppa eventi vicini nel tempo/spazio, calcola la severity)
│       ├── retention.py      # elimina le clip video più vecchie di VIDEO_RETENTION_MINUTES
│       └── server_monitor.py # campiona CPU, memoria e disco per la scheda "Server"
├── alembic/                   # migration DB (Alembic), generate da models.py
│   └── versions/
├── scripts/
│   ├── apply_migrations.sh   # applica le migration Alembic mancanti
│   └── create_admin.py       # crea il primo utente Admin da riga di comando
├── mosquitto/config/         # config del broker MQTT
├── docker-compose.yml
└── Dockerfile
```

## Migrazioni DB (Alembic)

Lo schema è generato da `app/db/models.py` tramite Alembic (`alembic/versions/`).
Il backend esegue `alembic upgrade head` automaticamente all'avvio del container
(vedi `Dockerfile`). Per applicarle a mano su un container già up:

```bash
./scripts/apply_migrations.sh
```

Dopo aver modificato un modello in `models.py`, genera la migration:

```bash
alembic revision --autogenerate -m "descrizione modifica"
```

`init_db_legacy_pre_alembic/` contiene i vecchi SQL a mano, tenuti solo come
riferimento storico — non vengono più eseguiti automaticamente.

## Flusso dati (sensore → pratica → dashboard)

1. Un device (telecamera IA, ESP32 reale, o nodo `mini_node` del modellino)
   pubblica un JSON su MQTT, topic `parco/<device_id>/events`.
2. `app/core/mqtt.py` riceve il messaggio, verifica che `device_id` combaci
   con un device già registrato (altrimenti scarta in silenzio), crea uno o
   più `Event` a seconda dei campi presenti nel payload.
3. Ogni evento passa per `services/correlation.py`, che lo aggancia a una
   `Practice` esistente (stessa zona, stessa categoria, aperta di recente)
   o ne crea una nuova.
4. Se l'evento supera certe soglie (vandalismo cestino, affollamento),
   `mqtt.py` pubblica comandi verso gli attuatori (`smartcity/actuators/*`)
   e registra l'allarme in `event_alarm`.
5. La dashboard riceve l'aggiornamento via WebSocket in tempo reale, e può
   anche interrogare `/practices`, `/mini/state`, ecc.

## Spazio su disco e monitoraggio del server

Le clip caricate dalla telecamera (`uploads/videos`) non restano per sempre:
`services/retention.py` elimina mp4, thumbnail e riga `event_video` delle clip
più vecchie di `VIDEO_RETENTION_MINUTES` (default 60, `0` = mai), con un
controllo ogni `VIDEO_CLEANUP_INTERVAL_SECONDS` (default 300). Snapshot
(`uploads/snapshots`) e clip del modellino (`uploads/mock_videos`) non vengono
toccati.

Allo stesso modo le segnalazioni (pratiche) create da più di
`PRACTICE_RETENTION_HOURS` (default 48, `0` = mai) vengono eliminate dal
database in qualunque stato, insieme ai loro eventi; gli eventi che non
generano pratiche (varchi, consumi) restano.

All'avvio il backend crea solo il parco e gli utenti demo: i dispositivi si
registrano dalla dashboard (Admin → Registrazione).

La dashboard Admin ha la scheda **Server** (`GET /sla/server`, solo admin):
uso della CPU negli ultimi 30 minuti, memoria, spazio su disco, peso delle
cartelle di upload e stato della pulizia, con un pulsante per eseguirla subito
(`POST /sla/server/cleanup`). In Docker CPU e memoria sono quelle della
macchina che ospita i container, non del solo backend.

## Avvio

```bash
docker compose up -d --build
```

Il backend applica le migration da solo all'avvio (`alembic upgrade head`).
Per riapplicarle senza riavviare il container:

```bash
./scripts/apply_migrations.sh
```

Per creare il primo utente Admin:

```bash
python scripts/create_admin.py
```

## Testare senza sensori reali

Bypassa completamente l'ESP32 e pubblica un evento a mano sul broker:

```bash
docker exec -it treeyes-mosquitto mosquitto_pub -t parco/<device_id>/events \
  -m '{"device_id":"<device_id>","full":90,"fill_level_pct":90,"tilt_angle":60}'
```

Per vedere il traffico MQTT grezzo in arrivo (utile per il debug):

```bash
docker exec -it treeyes-mosquitto mosquitto_sub -t 'parco/#' -v
```
