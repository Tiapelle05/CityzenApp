# Code review & security check — Treeyes / backend_evolved

Review del **2026-09-30** sull'intero backend (`app/`). Ordinata per gravità.
Legenda: 🔴 critico · 🟠 alto · 🟡 medio · 🟢 basso/hardening.

---

## 🔴 Critici

### C1 — Bypass autenticazione device tramite wildcard LIKE
`app/api/dependencies.py:55`
```python
device = db.query(Device).filter(Device.mac_address.ilike(x_mac_address.strip())).first()
```
`ilike` interpreta `%` e `_` come wildcard SQL. Un client che invia
`X-MAC-Address: %` matcha **qualsiasi** device e viene autenticato come il primo
in tabella — senza conoscere alcun MAC. Vale per `get_current_device` e, a
cascata, `get_current_camera` (upload snapshot/clip in `vision.py`, `/devices/me`).
**Fix:** confronto esatto case-insensitive senza wildcard, es.
`filter(func.lower(Device.mac_address) == x_mac_address.strip().lower())`.

### C2 — Autenticazione device senza segreto (solo MAC)
`app/api/dependencies.py:47-64`, `app/api/routers/vision.py`
L'unica credenziale del device è il MAC, che è **pubblico/prevedibile** (i MAC
demo sono in `init_defaults.py`). Chiunque conosca/indovini un MAC può caricare
snapshot e clip video associati agli eventi alert. Esiste già il modello `ApiKey`
(generato all'onboarding) ma **non viene mai verificato**. 
**Fix:** autenticare i device con l'API key (header dedicato) e verificarla contro
`ApiKey.active`; aggiornare `ApiKey.last_used`.

### C3 — Seed ripristina le password demo ad ogni avvio
`app/db/init_defaults.py:84-91`
Ad ogni avvio, se la password di un utente demo non è più `admin123`, viene
**riportata a `admin123`** (e sbloccato l'account). Un admin che cambia la
password se la ritrova resettata al riavvio. Con utenti `admin`/`modellino` di
tipo admin e `SHOW_DEMO_USERS=true` nel `.env`, è un accesso amministrativo
con credenziali note e non modificabili in modo persistente.
**Fix:** creare gli utenti demo solo se assenti e **solo** in ambiente di
sviluppo (flag esplicito); mai riscrivere una password esistente.

### C4 — SECRET_KEY debolissima
`.env: SECRET_KEY=chiave123` (e `.env.example` = `change-this-secret-key-in-production`)
Chiave di firma JWT banale e brute-forzabile: permette di **forgiare token**
per qualsiasi utente/ruolo (incl. admin). 
**Fix:** generare una chiave casuale ≥32 byte (`secrets.token_urlsafe(48)`),
validarne la lunghezza all'avvio, non committare valori di default deboli.

---

## 🟠 Alti

### A1 — Endpoint `/mini/*` senza autenticazione
`app/api/routers/mini_dashboard.py`
Sono **pubblici** (nessun `Depends(get_current_user)`):
`GET /mini/state`, `/mini/stream`, `/mini/alarms`, `/mini/videos`, `/mini/commands`,
`/mini/env-history`, `/mini/practices`, `GET /mini/settings`, e soprattutto
`POST /mini/alarms/{id}/reset` (riga 245-251).
Conseguenze: esposizione di stato device, pratiche, storico comandi MQTT; e
**chiunque può riarmare/spegnere sirena e LED polizia** di un allarme
(`reset_alarm`), oltre a leggere l'intera telemetria.
**Fix:** proteggere tutti gli endpoint con `get_current_user` e ruolo adeguato;
il reset deve essere riservato ai ruoli operativi/admin.

### A2 — 2FA (TOTP) non applicata al login
`app/api/routers/auth.py:22-62`, `app/api/routers/totp.py`
`login/access-token` emette un JWT pieno dopo la **sola verifica password**.
Gli endpoint `/auth/2fa/verify` esistono ma girano *dopo* aver già un token
valido e non condizionano l'accesso. Il 2FA è quindi puramente decorativo: un
utente con `totp_enabled=True` accede lo stesso senza codice.
**Fix:** se `totp_enabled`, il login deve restituire un token "parziale"/challenge
e richiedere la verifica TOTP prima di rilasciare il token completo.

### A3 — Nessun lockout né rate limiting sul login
`app/api/routers/auth.py`, `app/core/telegram.py:_cmd_login`
Il modello ha `failed_logins` e `locked_until`, ma il login **incrementa
`failed_logins` senza mai leggere/impostare `locked_until`**: nessun blocco.
Nessun rate limit su HTTP login né sul `/login` del bot Telegram → brute force
libero (per giunta con SECRET_KEY debole).
**Fix:** applicare lockout progressivo su `locked_until`, e rate limiting per IP
(es. slowapi) sugli endpoint di autenticazione.

### A4 — CORS completamente aperto
`app/main.py:39-45` → `allow_origins=["*"]`, `allow_methods=["*"]`, `allow_headers=["*"]`
Qualsiasi sito può chiamare l'API dal browser dell'utente. `allow_credentials=False`
attenua il furto cookie, ma i token sono comunque in header e l'API è del tutto
esposta a chiamate cross-origin.
**Fix:** whitelist esplicita di origin (dashboard) via config.

---

## 🟡 Medi

### M1 — Incompatibilità paho-mqtt 2.x
`app/core/mqtt.py:72` — `mqtt.Client(client_id="fastapi_backend", clean_session=True)`
`requirements.txt` fissa `paho-mqtt>=1.6.1`, che include la **2.x**, dove la
firma di `Client()` è cambiata (richiede `callback_api_version`): su
un'installazione pulita l'MQTT non parte.
**Fix:** pinnare `paho-mqtt<2` **oppure** migrare alla nuova API
(`mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, ...)`).

### M2 — Fallback silenzioso a SQLite in produzione
`app/db/database.py:10-23`
Se Postgres è irraggiungibile all'avvio, il sistema passa **senza errore** a
`sqlite:///./treeyes.db`. In produzione un blip di rete/DB fa ripartire il
backend su un DB locale vuoto/divergente, con perdita/split dei dati e, sotto
SQLite, datetime **naive** che rompono i confronti tz-aware (vedi M3).
**Fix:** in produzione fallire esplicitamente se il DB configurato non è
raggiungibile; il fallback SQLite solo dietro flag di sviluppo.

### M3 — Normalizzazione tipo evento incoerente (evento perso)
`app/core/mqtt.py:203-205`
La validazione usa `str(raw_type).strip().lower()`, ma l'`Event` viene creato con
`type=raw_type` (case originale). Un payload con `"type": "Alert"` supera il
check ma l'insert con `"Alert"` non è un valore valido dell'Enum → eccezione
catturata e **evento scartato silenziosamente**.
**Fix:** usare il valore normalizzato (`raw_type.strip().lower()`) anche in
`Event(type=...)`.

### M4 — IP di audit spoofabile
`app/api/routers/auth.py:17-19`, `totp.py:108-110`
`X-Forwarded-For` è preso dal client senza validare il proxy: gli IP negli
`AccessLog` sono falsificabili (impatto su audit/eventuale rate limiting per IP).
**Fix:** fidarsi di `X-Forwarded-For` solo se dietro proxy noto/configurato.

### M5 — Estensione file upload non validata
`app/api/routers/vision.py:140-146, 169-177`
`ext = os.path.splitext(file.filename)[1]` viene concatenato al path di salvataggio
senza whitelist né controllo del content-type. Il rischio path-traversal è basso
(il nome finale è generato dal server), ma un'estensione arbitraria/anomala può
comunque finire su disco.
**Fix:** whitelist estensioni (`.jpg/.png` per snapshot, `.mp4` per clip) e
validazione MIME; limitare la dimensione dell'upload.

---

## 🟢 Basso / hardening

- **B1** — Token WebSocket in query string (`/practices/ws?token=`,
  `practices.py:166`): può finire nei log di proxy/server. Già segnalato in un
  commento; valutare sottoprotocol header o cookie.
- **B2** — `ALGORITHM` è definito sia in `config.py` sia hardcoded in
  `security.py:7`; il valore di config non viene usato per firmare. Unificare.
- **B3** — `get_current_device` fa `db.commit()` ad ogni chiamata (update
  `last_seen`): con MAC noto è una scrittura DB non autenticata a costo zero per
  l'attaccante (amplifica C2).
- **B4** — Bot Telegram: credenziali inviate in chiaro nella chat con `/login`
  (restano nello storico Telegram); nessun rate limit sul comando.
- **B5** — `/mini` serve una pagina HTML che fa `fetch` su endpoint senza auth
  (coerente con A1: da chiudere insieme).
- **B6** — Nessun test automatico presente nel repo; le regressioni su pipeline
  MQTT/correlazione non sono coperte.

---

## Riepilogo priorità

| # | Titolo | Gravità | File |
|---|--------|---------|------|
| C1 | Bypass auth device via LIKE wildcard | 🔴 | dependencies.py:55 |
| C2 | Device auth senza segreto (ApiKey inutilizzata) | 🔴 | dependencies.py, vision.py |
| C3 | Seed resetta password demo ad ogni avvio | 🔴 | init_defaults.py:84 |
| C4 | SECRET_KEY debole (`chiave123`) | 🔴 | .env |
| A1 | Endpoint `/mini/*` senza auth (incl. reset allarme) | 🟠 | mini_dashboard.py |
| A2 | 2FA non applicata al login | 🟠 | auth.py, totp.py |
| A3 | Nessun lockout / rate limit login | 🟠 | auth.py, telegram.py |
| A4 | CORS `*` | 🟠 | main.py:39 |
| M1 | Incompatibilità paho-mqtt 2.x | 🟡 | mqtt.py:72 |
| M2 | Fallback silenzioso a SQLite | 🟡 | database.py |
| M3 | Normalizzazione type evento incoerente | 🟡 | mqtt.py:203 |
| M4 | IP audit spoofabile | 🟡 | auth.py:17 |
| M5 | Estensione upload non validata | 🟡 | vision.py |
