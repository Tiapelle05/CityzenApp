# Tryees – app Flutter collegata al backend

## Avvio del backend

1. Estrarre l'archivio `tryees_backend_integrato.zip`.
2. Aprire un terminale nella cartella `tryees_backend` (quella con `docker-compose.yml`).
3. Eseguire:

   ```bash
   docker compose up -d --build
   ```

4. Verificare `http://localhost:8000/`. La risposta attesa è un JSON con `status: ok`.
5. Dashboard: `http://localhost:5173/`.

Il Compose avvia PostgreSQL, Mosquitto, FastAPI e la dashboard. PostgreSQL viene
inizializzato automaticamente; il backend esegue le migrazioni Alembic all'avvio.
Non serve creare manualmente un database né un file `.env` per il primo avvio locale.

## Avvio Flutter

Questo archivio contiene `pubspec.yaml` nella radice del progetto, come richiesto da
Flutter. Aprire questa cartella in Android Studio oppure entrare qui da terminale.

```bash
flutter pub get
flutter run -d chrome
```

Per un emulatore Android:

```bash
flutter run
```

L'app usa automaticamente `http://10.0.2.2:8000` su Android Emulator e
`http://localhost:8000` su Chrome/desktop.

Per un telefono Android o iPhone fisico collegato alla stessa rete Wi-Fi del PC, sostituire
`192.168.1.10` con l'indirizzo IPv4 del PC (visibile con `ipconfig` su Windows):

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

Il firewall del PC deve consentire le connessioni in ingresso sulla porta 8000.

## Funzionalità collegate

- Registrazione anonima dell'installazione e conservazione del token.
- Schermata Inizio: stato reale del parco dal backend.
- Segnala: categoria, priorità, acquisizione GPS, foto facoltativa e invio multipart.
- Idee: invio pubblico/privato, elenco pubblico, ordinamento e voti persistenti.
- Avvisi: elenco e filtri alimentati dagli avvisi attivi del backend.

La selezione automatica usa il primo parco attivo nel database. Il seed iniziale crea
`Parco Robinson` a Legnano. Il backend accetta una segnalazione `problem` solo se il
GPS è entro il raggio configurato del parco (500 metri se non è impostato un raggio
specifico). Per testare l'invio della segnalazione, occorre quindi trovarsi nell'area
del parco configurato.

## URL backend

- API: `http://localhost:8000`
- Health check: `http://localhost:8000/`
- Documentazione API: `http://localhost:8000/docs`

I valori di sicurezza predefiniti del Compose sono adatti solo allo sviluppo locale.
Non esporre il backend su Internet senza sostituire le credenziali e `SECRET_KEY`.

## Dati ambientali e assistente

Nuove funzioni dell'app (guida backend `docs/citizen-app/GUIDA_AMBIENTE_ASSISTENTE.md`):

- **Barra in basso**: Inizio · Segnala · **Mappa** (al centro) · Aria · Parky. Idee si aprono
  dalle scorciatoie della Home, gli Avvisi dalla campanella in alto (con il numero di quelli attivi).
- **Card "Aria nel parco"** in Home, in versione compatta sopra l'anteprima della mappa: qualità dell'aria,
  temperatura, polveri e umidità della prima stazione; grigia se i dati non sono aggiornati.
- **Banner di allerta aria** in Home (arancione o rosso), dai messaggi WebSocket e dai
  livelli delle letture. Non è un avviso di pericolo: nessuna finestra in primo piano.
- **Scheda Aria** (schermata Ambiente): una card per metrica (valore, variazione nell'ultima ora, minimo e
  massimo delle 24 ore, mini-curva, livello per polveri e gas) e il **grafico** a 24 h, 7 e
  30 giorni, con i buchi nei dati lasciati vuoti.
- **Parky** (scheda della barra in basso): chat con l'assistente del parco, domande suggerite, fonti che aprono la
  schermata giusta, errori 429 / 503 / rete gestiti con messaggi chiari e Riprova.

### Struttura del codice

| Cartella | Contenuto |
|---|---|
| `lib/modelli/ambiente.dart` | Modelli Dart: `EnvMetric`, `ParkEnvironment`, `EnvStation`, `StationReading`, `EnvSeries`, `AssistantReply`, messaggi WebSocket |
| `lib/api/treeyes_api.dart` | Interfaccia `TreeyesApi` (4 metodi) |
| `lib/api/http_treeyes_api.dart` | Implementazione sul backend (usa il trasporto di `CitizenApi`: token, 401, errori) |
| `lib/api/mock_treeyes_api.dart` | Implementazione con i JSON di `Assets/mock/`, usata in demo e nei test |
| `lib/ambiente/` | Stato condiviso (`StatoAmbiente`), card, banner, schermata Ambiente, grafici, formattazione |
| `lib/assistente/` | Chat con l'assistente Parky (nome in `nomeAssistente`) |

`CitizenApi.instance.treeyes` restituisce il mock in demo e l'implementazione HTTP con il
server.

### Endpoint usati

| Metodo e percorso | Uso |
|---|---|
| `GET /citizen/environment/metrics` | Catalogo metriche (tenuto in memoria per la sessione) |
| `GET /citizen/parks/{id}/environment` | Home e Ambiente; ricaricato ogni 60 s mentre la Home è visibile |
| `GET /citizen/parks/{id}/environment/series?metric=&range=&station_id=` | Grafico (`24h`, `7d`, `30d`) |
| `POST /citizen/parks/{id}/assistant` | Assistente (timeout di 50 s; ultimi 10 turni di cronologia) |

Messaggi WebSocket `/citizen/ws` gestiti: `environment_reading` (aggiorna i valori),
`environment_alert` (banner), `environment_alert_ended` (chiude il banner della stazione).
I `type` sconosciuti vengono ignorati.

### Pacchetti aggiunti

- **fl_chart**: grafici a linee nativi in Flutter, senza servizi esterni; supporta le
  interruzioni della linea (buchi nei dati) e la banda minimo–massimo.
- **intl**: numeri all'italiana (virgola decimale) con i decimali del catalogo metriche.

### Provare gli scenari

In demo, dal pulsante con la provetta nella schermata Ambiente si sceglie lo scenario:
normale, polveri alte (banner e card arancione), stazione spenta (card grigia), gas in
preriscaldamento (gas "—"). In alternativa all'avvio:

```bash
flutter run --dart-define=DEMO=true --dart-define=ENV_SCENARIO=dust_high
```

Con il backend vero lo scenario si imposta lato server con `ENV_MOCK_SCENARIO`.

### Limiti

- I dati ambientali sono indicativi: sensori a basso costo, non certificati. Le etichette
  "Buona", "Scarsa"… non sono giudizi sanitari.
- L'assistente risponde a regole finché il backend non attiva un modello linguistico; a quel
  punto va aggiornata l'informativa privacy. La conversazione resta solo in memoria.
- Screenshot da allegare alla consegna: card in Home, schermata Ambiente, grafico, chat.
