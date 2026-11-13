# Design — API del cittadino (`/citizen`)

> Stato: decisioni D1–D5 prese (§14), pronto per l'implementazione. 2026-10-28.
> Contratto di riferimento: deck "Treeyes – Citizen App Flutter (brief tecnico)",
> slide 12–27, l'unico che contiene gli esempi JSON. **Salvo dove indicato, i numeri di
> slide in questo documento si riferiscono a quel deck.** I formati JSON non cambiano:
> il team Flutter li sta già usando nei mock. Il deck mostrato agli studenti è la
> versione ridotta "Treeyes – Citizen App Flutter": l'allineamento è in §12.

## 1. Obiettivo e vincoli

L'app Flutter deve poter: registrarsi in forma anonima, leggere parchi, stato del
parco, avvisi e categorie, inviare problemi / suggerimenti / feedback con posizione e
foto, seguire le proprie segnalazioni, ricevere aggiornamenti live.

Vincoli che vengono dal codice di oggi:

| Vincolo | Dove | Conseguenza per il design |
|---|---|---|
| Tutte le API esistenti richiedono un JWT operatore e restituiscono dati interni | `dependencies.py`, `practices.py` | Router nuovo, token nuovo, formattazione dedicata: nessun riuso dei `_fmt_*` operatori |
| `user_from_token` accetta qualunque JWT firmato con `sub` = username | `dependencies.py:20` | Va aggiunto un controllo di `scope`, altrimenti un token cittadino potrebbe valere come operatore |
| `Event.mac_address` è `NOT NULL` + FK a `device` | `models.py:64` | L'evento "citizen" non ha un device: la colonna diventa nullable |
| La correlazione prende lat/lon/zona dal device e fonde solo a parità di zona, entro 15 min | `correlation.py:90-99,143` | Per gli eventi citizen posizione e zona arrivano dalla segnalazione; finestra più lunga |
| `_sev` fa la media dei pesi: un evento leggero abbassa la severità di una pratica | `correlation.py:55` | Gli eventi citizen non entrano nella media, danno solo un bonus |
| La retention cancella le pratiche dopo 48 h, in qualunque stato | `retention.py:165` | Lo stato della segnalazione vive in una tabella propria, che sopravvive alla pratica |
| `ws_manager` fa broadcast a tutti i connessi | `ws_manager.py:15` | Gestore WebSocket separato, con invio mirato al singolo cittadino |
| `/static` è pubblico, senza login | `main.py:72` | Le foto hanno nomi casuali non indovinabili (vedi §10, decisione aperta D4) |
| `Practice.park_id` non viene mai impostato dalla correlazione (resta il default 1) | `correlation.py:127` | Va valorizzato: lo stato del parco filtra per `park_id` |

## 2. Decisioni chiave in breve

1. **Router separato** `app/api/routers/citizen.py`, montato su `/citizen`, con una sua
   dipendenza `get_current_citizen`. Le API operatori non cambiano comportamento.
2. **Token cittadino** = JWT HS256 con `scope: "citizen"`, durata 30 giorni. Le API
   operatori rifiutano esplicitamente questo scope.
3. **La segnalazione è la fonte di verità per il cittadino** (`citizen_report` + storico).
   Per i soli *problemi* il backend crea anche un `Event` di tipo `citizen` che entra
   nella correlazione come qualunque sensore. Suggerimenti e feedback non diventano
   eventi né pratiche.
4. **Lo stato della segnalazione segue la pratica** (`open→received`,
   `in_progress→in_progress`, `resolved→resolved`, `closed→closed`). Ogni passaggio viene
   salvato nello storico e inviato al cittadino via WebSocket.
5. **Lo stato del parco non espone mai la sicurezza.** Si calcola dalle pratiche non di
   sicurezza e dagli avvisi pubblicati dagli operatori. Il livello `alert` lo decide
   solo un avviso scritto da una persona, mai un allarme automatico.

## 3. Modello dati

### Tabelle nuove

```text
citizen
  id             PK int
  public_id      str unique         "c_7Hq2LmX9" — compare nel token e nella risposta
  install_hash   str(64) unique     sha256(install_id): l'install_id in chiaro non si salva
  platform       str                android | ios
  app_version    str
  blocked        bool default false blocco manuale in caso di abuso
  created_at, last_seen_at

citizen_category                    seed in init_defaults.py, modificabile a DB
  code           PK str             lighting, waste, …
  label          str                "Illuminazione"
  icon           str                nome icona Material
  kinds          str                "problem,suggestion"
  practice_category  str            security | basket | soil | other (vedi §6.1)
  merge_types    str                tipi evento sensore con cui può fondersi, "light,is_dark"
  sort_order     int
  active         bool

citizen_report
  id             PK int
  citizen_id     FK citizen ON DELETE CASCADE
  park_id        FK park
  kind           str                problem | suggestion | feedback
  category       FK citizen_category.code, nullable (feedback)
  description    str(1000)
  priority       str nullable       low | medium | high (solo problem)
  lat, lon       float nullable
  rating         int nullable       1..5 (solo feedback)
  photo_path     str nullable       "citizen/3f9c….jpg" relativo a UPLOAD_DIR
  client_ref     str(36)
  status         str                received | in_progress | resolved | closed
  practice_id    FK practice ON DELETE SET NULL, nullable
  event_id       FK event ON DELETE SET NULL, nullable
  created_at, updated_at
  UNIQUE (citizen_id, client_ref)          idempotenza dei reinvii
  INDEX  (citizen_id, created_at)          "le mie segnalazioni"
  INDEX  (practice_id)                     propagazione stato

citizen_report_history
  id, report_id FK citizen_report ON DELETE CASCADE
  status, note nullable (visibile al cittadino), at

park_notice                          avvisi scritti dagli operatori
  id, park_id FK park
  title str(120), body str(1000), level info | warning | alert
  starts_at, ends_at nullable
  created_by FK app_user, created_at

event_citizen                        dettaglio polimorfo, come event_soil & co.
  event_id   PK FK event ON DELETE CASCADE
  report_id  FK citizen_report ON DELETE SET NULL
  lat, lon, category, priority
```

### Modifiche a tabelle esistenti

- `TypeEvent` + valore `citizen` (`ALTER TYPE type_event ADD VALUE IF NOT EXISTS 'citizen'`,
  come nella migrazione `9665f22103bf`).
- `event.mac_address` → nullable. Da sistemare di conseguenza: `schemas/event.py`
  (`mac_address: str | None`) e `GET /events`, che deve escludere il tipo `citizen`
  (gli operatori le vedono dentro le pratiche, e `op_eco` oggi vedrebbe anche le
  segnalazioni di sicurezza).
- `park.radius_m` float nullable: raggio entro cui una posizione è "dentro il parco".
  Se è nullo vale `CITIZEN_PARK_RADIUS_M` (default 500).

Una sola migrazione Alembic, dopo `a1b2c3d4e5f6`.

### Perché un `Event` senza device e non un device virtuale

Un device fittizio "citizen" per parco comparirebbe negli elenchi device, nell'SLA e nel
controllo offline (`last_seen`), e andrebbe escluso in ogni punto. Con `mac_address` nullo
i punti da toccare sono solo due (`schemas/event.py` e `/events`). La correlazione gestisce
già un `dev` assente (`correlation.py:91`).

## 4. Autenticazione del cittadino

**`POST /citizen/register`** riceve `install_id` (UUID v4), `platform` e `app_version`.

1. Calcola `sha256(install_id)` e cerca il cittadino. Se non esiste lo crea
   (`public_id` = `"c_"` + 8 caratteri base62 casuali). Restituisce 201 se nuovo, 200 se
   già esistente: in entrambi i casi stesso cittadino e stesso storico (slide 15).
2. Se il cittadino è `blocked` → 403.
3. Emette il JWT `{"sub": "citizen:<public_id>", "scope": "citizen", "exp": +30 giorni}`.

**`get_current_citizen`** (in `dependencies.py`): header `Authorization: Bearer`, decodifica,
`scope == "citizen"` obbligatorio, carica il `Citizen` per `public_id`, 401 se manca o non
è valido, 403 se è bloccato.

**Separazione dagli operatori.** In `user_from_token` si aggiunge una riga:
`if payload.get("scope") == "citizen": return None`. Senza questa riga la difesa si
regge solo sul prefisso `citizen:` del `sub`. Con la riga, un token cittadino non apre
nessuna API operatore, WebSocket `/practices/ws` incluso.

**Modello di minaccia accettato per il PoC.** L'`install_id` è l'unico segreto: chi lo
conosce si presenta come quel cittadino. Lascia il telefono solo nella chiamata di
registrazione e nel DB c'è solo il suo hash. Non dà accesso a nulla oltre alle
segnalazioni di quel cittadino.

## 5. Endpoint

Regole comuni come da slide 12: JSON in snake_case, date ISO 8601 UTC con `Z`, errori come
`{"detail": …}`, paginazione `skip`/`limit` (`limit` ≤ 50). Tutti gli endpoint tranne
`register` richiedono il token cittadino.

| Metodo e percorso | Logica | Errori |
|---|---|---|
| `POST /citizen/register` | §4 | 422, 429 (rate limit per IP) |
| `GET /citizen/parks` | Parchi `active`: `id, name, city, lat, lon` | — |
| `GET /citizen/parks/{id}/status` | §7 | 404 parco inesistente o non attivo |
| `GET /citizen/parks/{id}/notices` | Avvisi attivi adesso (`starts_at ≤ now` e `ends_at` nullo o futuro), ordinati per livello e poi per data | 404 |
| `GET /citizen/categories` | Categorie `active` per `sort_order`; `kinds` restituito come lista | — |
| `POST /citizen/reports` | §5.1 | 404 parco, 422 (anche foto troppo grande o non valida), 429 |
| `GET /citizen/reports?kind=problem` | Solo `citizen_id` = chiamante, ordine `created_at desc`, `{items, total}`; `kind` è opzionale (`problem`, `suggestion`, `feedback`); `summary` = prime 80 lettere della descrizione | — |
| `GET /citizen/reports/{id}` | Dettaglio + `history`. Una segnalazione di un altro cittadino → **404**, non 403, per non rivelarne l'esistenza (come `_get_accessible`) | 404 |
| `WS /citizen/ws?token=` | §8 | chiusura 1008 |

Etichette di stato (`status_label`) e `code` (`SEG-{anno}-{id:06d}`) le calcola il backend.

### 5.1 `POST /citizen/reports`

Sempre `multipart/form-data`. Ordine dei controlli:

1. **Idempotenza.** Se `(citizen_id, client_ref)` esiste già → **200** con la segnalazione
   esistente. Non si ricrea nulla e la foto non si salva di nuovo. Va fatto prima del rate
   limit: un reinvio dopo un errore di rete non deve consumare il limite.
2. **Rate limit.** Più di `CITIZEN_REPORTS_PER_HOUR` (default 10) segnalazioni del
   cittadino nell'ultima ora → 429 con `Retry-After`. Il conteggio si fa su DB: è
   corretto anche con più worker.
3. **Validazione per `kind`** (slide 18):

   | Campo | problem | suggestion | feedback |
   |---|---|---|---|
   | `category` | obbligatoria, `kind` ammesso dalla categoria | obbligatoria, idem | facoltativa |
   | `description` | 10–1000 | 10–1000 | 10–1000 |
   | `priority` | facoltativa, default `medium` | ignorata | ignorata |
   | `lat`, `lon` | obbligatori | facoltativi | facoltativi |
   | `rating` | ignorato | ignorato | obbligatorio 1–5 |
   | `photo` | facoltativa | facoltativa | rifiutata (422) |

4. **Posizione nel parco.** Se ci sono `lat`/`lon`: distanza haversine dal centro del parco
   ≤ `radius_m`, altrimenti 422 `"La posizione indicata è fuori dal parco"`.
5. **Foto** (§10): validata e ricodificata *prima* di scrivere sul DB. Il file si scrive
   prima del commit e si cancella se il commit fallisce (anche per un `client_ref`
   inviato due volte in contemporanea): non restano né file orfani né righe senza file.
6. **Scrittura.** `citizen_report` (status `received`) + prima riga di storico. Per
   `kind=problem` si aggiungono `Event(type=citizen, mac_address=None)` + `event_citizen`
   e si chiama la correlazione (§6). Poi `ws_manager` notifica gli operatori come fa
   `_correlate` in `mqtt.py:579`.
7. Risposta **201** nel formato della slide 18.

## 6. Integrazione con correlazione e pratiche

### 6.1 Da categoria cittadino a pratica

La mappatura sta nella tabella `citizen_category`, non nel codice:

| code | practice_category | merge_types | Chi la vede in dashboard |
|---|---|---|---|
| lighting | security | light, is_dark | ente, admin |
| safety | security | — | ente, admin |
| waste | basket | full, weight, battery | op_eco, admin |
| green, irrigation | soil | humidity, eco | op_eco, admin |
| fountains, furniture, cleaning, play, other | other | — | **solo admin** oggi (D2) |

`lighting` va in `security` perché è lì che finiscono oggi gli eventi sensore `light` e
`is_dark` (`correlation.py:23`). È l'unico modo per unire nella stessa pratica cittadino e
lampione (slide 23). La conseguenza è che le segnalazioni di illuminazione arrivano alla
polizia e non alla manutenzione: vedi D2.

### 6.2 Modifiche a `CorrelationEngine.process_event`

Per `ev_type == "citizen"`:

- **Posizione**: da `event_citizen`, non dal device.
- **Zona**: quella del device più vicino dello stesso parco entro
  `CITIZEN_ZONE_SNAP_M` (75 m). Se non ce n'è nessuno la zona è nulla, e la segnalazione
  si fonde solo con altre segnalazioni dei cittadini senza zona. Senza questo passaggio
  `_find` non la unirebbe mai a un sensore, perché la zona fa parte della chiave.
- **Finestra**: `CITIZEN_WINDOW_HOURS` (24 h) invece di 15 min. Una panchina rotta resta
  rotta: due cittadini che la segnalano a 3 ore di distanza devono finire nella stessa
  pratica. La finestra vale in entrambi i sensi: è di 24 h anche quando un evento sensore
  cerca una pratica che contiene segnalazioni. Così il lampione che si guasta (o viene
  rilevato) due ore dopo la segnalazione finisce nella stessa pratica (slide 12 del deck).
- **Compatibilità** (nuovo filtro in `_find`, che vale *solo* se c'è di mezzo un evento
  citizen): una pratica candidata va bene se tutti i suoi eventi sono di tipo `merge_types`
  della categoria oppure segnalazioni della stessa categoria cittadino. Vale anche
  nell'altro senso: un evento sensore entra in una pratica che contiene segnalazioni solo
  se il suo tipo è nei `merge_types`. Senza questo filtro un "lampione spento" potrebbe
  finire dentro una pratica "Rissa in corso" della stessa zona, o una telecamera dentro
  una pratica di illuminazione. Tra soli sensori il comportamento non cambia.
- **Titolo**: `"Segnalazione cittadino: {label} – {zona o 'posizione indicata'}"`.
- **`park_id`**: dalla segnalazione. Già che ci siamo, per i sensori si prende da
  `device.park_id`.

**Severità.** Le segnalazioni non entrano nella media di `_sev`. Una pratica fatta solo di
segnalazioni parte dal peso della priorità (`low` 2, `medium` 3, `high` 5). Ogni
segnalazione in più aggiunge +0,5, fino a +2. Una segnalazione non porta mai una pratica
sopra 7 né la fa scendere. Questo realizza il "la segnalazione rafforza la pratica" della
slide 23.

### 6.3 Propagazione dello stato

Nuova funzione `sync_reports(db, practice, note=None)` in `app/services/citizen.py`,
chiamata da:

- `PATCH /practices/{id}/status` e `POST /practices/{id}/archive`;
- la correlazione, quando una segnalazione si unisce a una pratica già `in_progress`.
  La segnalazione passa subito a `in_progress`, e lo storico mostra
  `received → in_progress`.

Per ogni `citizen_report` collegato con stato diverso da quello della pratica: aggiorna,
aggiunge una riga di storico con la nota e invia `report_updated` al cittadino.
`StatusBody` riceve un campo facoltativo `citizen_note`, mostrato in dashboard come
"Nota visibile al cittadino". Le note interne non arrivano mai all'app.

**Pratica cancellata** (retention a 48 h o `DELETE` admin). Prima della cancellazione,
`detach_reports(db, practice_ids)` porta a `closed` le segnalazioni non ancora
`resolved`/`closed`, con la nota "Chiusa automaticamente". Poi la FK va a `NULL`. Il
cittadino conserva storico, testo e foto (slide 27). Vedi D1.

### 6.4 Cosa vedono gli operatori

`_fmt_event` aggiunge un `detail` per `citizen`: `report_code, kind, category, description,
priority, photo_url`. **Nessun identificativo del cittadino.** Servono piccole modifiche alle
dashboard React per mostrare testo e foto.

## 7. Stato del parco

`GET /citizen/parks/{id}/status`, calcolato a ogni richiesta (con un solo parco e poche
pratiche costa una query):

1. **Pratiche considerate**: del parco, `open`/`in_progress`, con categoria pubblica non
   nulla. La categoria pubblica è:
   - la categoria della prima segnalazione collegata, purché non sia `safety`;
   - altrimenti `basket → waste` e `soil → green`;
   - altrimenti nessuna (esclusa).

   Le pratiche di sicurezza dei sensori, le telecamere e le segnalazioni `safety` non
   compaiono mai, né nei conteggi né negli highlights (slide 5).
2. `open_issues` = numero di pratiche considerate; `highlights` = conteggio per categoria
   pubblica, con la `label` presa da `citizen_category`.
3. **Livello**: `alert` se c'è un avviso attivo di livello `alert`; altrimenti `warning`
   se `open_issues > 0` o c'è un avviso `warning`; altrimenti `ok`. `message` è il testo
   fisso del livello (slide 16).
4. `updated_at` = data più recente tra pratiche e avvisi considerati.

Quando cambia una pratica, una segnalazione o un avviso, il backend ricalcola il livello
del parco. Se è diverso dall'ultimo inviato (tenuto in memoria per parco), manda
`park_status_changed`; per gli avvisi appena entrati in corso manda `notice_created`.
Lo fanno subito le API (cambio di stato, cancellazione, avvisi, nuove segnalazioni) e
`park_watch_loop` ogni 30 secondi per tutto il resto: eventi dei sensori via MQTT (così
`mqtt.py` non cambia), retention, avvisi programmati che iniziano o scadono.

## 8. WebSocket `/citizen/ws`

- Nuovo `CitizenConnectionManager` in `app/core/citizen_ws.py`, separato da `ws_manager`.
  Così un messaggio operatore non può arrivare a un cittadino nemmeno per errore.
  Struttura: `dict[citizen_id, set[WebSocket]]` (stesso cittadino su più dispositivi), con
  `send_to_citizen` e `broadcast_park` e le varianti `*_from_thread` come in `ws_manager`
  (gli endpoint sincroni girano nel threadpool).
- Token non valido o cittadino bloccato → `accept()` + `close(1008)`, come in `practices.py:186`.
- Al massimo 5 connessioni per cittadino: alla sesta si chiude la più vecchia (codice 1000).
- Messaggi in arrivo: si accetta `"ping"` e si ignora il resto. Il server non manda
  messaggi fuori dallo schema `{type, data}` della slide 21.
- `report_updated` → solo al proprietario. `notice_created` e `park_status_changed` → a
  tutti i cittadini connessi, con `park_id` nei dati: l'app filtra sul suo parco. Con un
  parco solo basta. Con più parchi si aggiunge `?park_id=` all'URL.
- Limite: il gestore vive nel processo. Oggi c'è un solo worker uvicorn (`Dockerfile:17`).
  Con più worker servirebbe un pub/sub (es. Redis), e lo stesso problema c'è già per
  `/practices/ws`.

## 9. Lato operatori (necessario per l'MVP)

| Cosa | Dove | Chi |
|---|---|---|
| Avvisi: `GET/POST /parks/{id}/notices`, `PATCH/DELETE /parks/{id}/notices/{nid}` | `parks.py` | admin; op_eco per `info`/`warning` |
| Suggerimenti e feedback: `GET /citizen-reports?kind=`, `PATCH /citizen-reports/{id}/status` | nuovo `citizen_ops.py`, auth operatore | admin |
| Segnalazioni dentro le pratiche | `_fmt_event` (§6.4) | come la pratica |
| Schermata "Avvisi" e scheda "Suggerimenti" | `webapp/` | — |

Il nome `/citizen-reports` rende chiaro che è un'API operatore. Rientra nelle "API
operatori: /practices, /devices…" che la slide 7 del deck ridotto vieta all'app.

## 10. Protezioni

- **Foto**: si leggono al massimo 5 MB a blocchi (oltre → 422, perché il deck elenca solo
  400/403/404/422/429/5xx); Pillow `open` + `verify`;
  formati ammessi solo JPEG/PNG (lo decide il contenuto, non l'estensione: vedi M5 della
  security review); `Image.MAX_IMAGE_PIXELS` = 40 MP contro le decompression bomb;
  ridimensionamento al lato massimo 1600 px; ricodifica in JPEG qualità 85 **senza EXIF**
  (la ricodifica toglie anche il GPS della foto); nome `uploads/citizen/<secrets.token_hex(16)>.jpg`.
  Aggiungere `Pillow` esplicito in `requirements.txt` (oggi arriva solo tramite `qrcode[pil]`).
- **Rate limit**: segnalazioni su DB (§5.1); `register` in memoria per IP, 20/ora. L'IP è
  `request.client.host`, non `X-Forwarded-For` (vedi M4 della security review).
- **Testo**: nessun HTML interpretato da nessuna parte. La dashboard React fa già escape;
  il bot Telegram usa `parse_mode=HTML`, quindi se inoltra testo dei cittadini va fatto
  escape.
- **Posizione** verificata sul raggio del parco (§5.1). Un poligono vero è un'evoluzione
  futura.
- **Swagger**: `/docs` mostra anche le API operatori. Si aggiunge l'impostazione
  `ENABLE_DOCS` (default true in sviluppo) e uno schema filtrato su `/citizen/openapi.json`
  con i soli path `/citizen`, da usare con `openapi-generator` (slide 12), che altrimenti
  genererebbe anche i modelli operatore.
- **Esposizione**: in sviluppo l'app chiama `:8000` direttamente (slide 10). In produzione
  servono HTTPS e un `location` nel reverse proxy per `/citizen` e `/citizen/ws` con gli
  header di upgrade. Oggi `webapp/nginx.conf:41` non include `/citizen`.

## 11. Retention e privacy

- `citizen_report` e il suo storico sopravvivono alla pratica (§6.3). Si
  cancellano `CITIZEN_REPORT_RETENTION_DAYS` (30, D5) giorni dopo il passaggio a
  `resolved`/`closed`, foto compresa, con un nuovo job in `retention_loop`. Un `citizen`
  senza segnalazioni e inattivo da 12 mesi si cancella.
- **L'informativa attuale non copre l'app.** "Informativa privacy – Parco.pdf" parla solo
  di telecamere, microfoni e sensori. Prima di distribuire l'app serve una sezione (o
  un'informativa a parte) su: identificativo anonimo dell'installazione, testo, posizione,
  foto, finalità (gestione delle segnalazioni), base giuridica, conservazione (il punto
  sopra), destinatari. Il Profilo dell'app la deve linkare (slide 24).
- Nel modulo, l'avviso "non scrivere dati personali, niente volti o targhe" è a carico
  dell'app (slide 22). Lato server la ricodifica toglie gli EXIF, ma non può togliere un
  volto dalla foto.

## 12. Allineamento con il deck

Il deck di riferimento ora è "Treeyes – Citizen App Flutter.pptx" (17 slide; il "brief
tecnico" da 29 slide è la versione precedente). Correzioni già applicate il 2026-10-28:

| Slide | Prima | Ora |
|---|---|---|
| 10 | Errori "400 / 404"; modelli Dart da `/openapi.json` | "400 / 403 / 404" (403 = cittadino bloccato); `/citizen/openapi.json` (§10) |
| 12 | Il sensore invia "un consumo anomalo"; "entro 50 m e 15 minuti"; notifiche "dashboard e Telegram" | Anomalia della luce (`light`/`is_dark`: gli eventi `power` non generano pratiche, `correlation.py:85`); 24 ore (§6.2); solo dashboard (D3). Note del relatore allineate |
| 13 | "Foto e posizione visibili solo agli operatori" | "Foto e posizione mai mostrate ad altri cittadini" (D4) + nuovo punto "Segnalazioni chiuse cancellate dopo 30 giorni" (D5). Note allineate |
| 14 | Le note citavano "il codice in basso", tolto dalla slide | Note corrette |

Cose che il nuovo deck non dice più, perché erano nelle slide tecniche tolte, e che vanno
comunicate al team Flutter insieme allo schema OpenAPI:

- un reinvio con lo stesso `client_ref` risponde **200** con la segnalazione già esistente
  invece di 201: l'app deve trattare ogni 2xx come successo (`dio` lo fa già);
- `photo_url` ha un nome casuale (`/static/citizen/3f9c….jpg`): l'app usa l'URL così com'è.

## 13. Piano di implementazione

**Stato: tutte e sei le fasi sono implementate** sul branch `feature/citizen-api`, una
fase per commit. Restano fuori: la sezione Avvisi nella dashboard eco (le API la
permettono già a `op_eco`), il reverse proxy HTTPS per esporre `/citizen` in produzione
(§10) e l'informativa privacy dell'app (§11).

Ordine scelto per sbloccare il team Flutter il prima possibile (le loro tappe 3–5 della
slide 26 hanno bisogno delle prime due fasi):

1. **Fondamenta**: modelli e migrazione, `scope` in `user_from_token`,
   `get_current_citizen`, `register`, `parks`, `categories` con seed.
2. **Segnalazioni**: `POST`/`GET /citizen/reports`, foto, idempotenza, rate limit,
   verifica posizione. In questa fase le segnalazioni si salvano senza correlazione.
3. **Correlazione e stato**: evento `citizen`, modifiche a `correlation.py`, `sync_reports`
   / `detach_reports`, `citizen_note`, dettaglio in `_fmt_event`, esclusione da `/events`.
4. **Stato del parco e avvisi**: `/status`, `/notices`, API avvisi lato operatori, schermata
   in dashboard.
5. **Tempo reale**: `citizen_ws.py`, `/citizen/ws`, i tre messaggi.
6. **Rifinitura**: retention delle segnalazioni (D5) e delle pratiche senza video (D1),
   `/citizen/openapi.json`, `ENABLE_DOCS`,
   scheda "Suggerimenti" in dashboard, aggiornamento di `CONTEXT.md` e del deck (§12).
   Per D1 una pratica conta "con video" se ha almeno un evento di un device telecamera o
   microfono, oppure con dettaglio camera/microfono (anche gli allarmi sintetici).

File toccati: nuovi `routers/citizen.py`, `routers/citizen_ops.py`, `services/citizen.py`,
`core/citizen_ws.py`, `schemas/citizen.py` e una migrazione; modificati `models.py`,
`dependencies.py`, `correlation.py`, `practices.py`, `parks.py`, `events.py`,
`schemas/event.py`, `retention.py`, `init_defaults.py`, `config.py`, `main.py`,
`requirements.txt`.

## 14. Decisioni (prese il 2026-10-28)

| # | Domanda | Decisione |
|---|---|---|
| D1 | Una pratica nata da una segnalazione veniva cancellata dopo 48 h anche se nessuno l'aveva risolta | Le pratiche **senza eventi di telecamera o microfono** si conservano **30 giorni** (nuova impostazione `PRACTICE_RETENTION_DAYS_NON_SECURITY`, default 30). Le altre restano a 48 h, come da informativa. `detach_reports` (§6.3) serve ancora per la cancellazione admin e per le pratiche scadute ancora aperte |
| D2 | Chi vede in dashboard illuminazione e arredi | **Nessun cambio**: `lighting` resta in `security` (polizia), fontanelle/arredi/pulizia/giochi/altro restano in `other` (solo admin). L'admin le smista |
| D3 | Telegram per le segnalazioni `safety` | **Nessuna notifica**: la polizia le vede solo in dashboard |
| D4 | Foto su `/static` o endpoint autenticato | **`/static` con nome casuale** (§10) |
| D5 | Conservazione delle segnalazioni chiuse | **30 giorni** dopo `resolved`/`closed`: `CITIZEN_REPORT_RETENTION_DAYS` = 30. Va scritto nell'informativa |
