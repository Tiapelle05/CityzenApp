# Treeyes Dashboard

Webapp del centro operativo: una dashboard per ogni profilo, aggiornata in tempo reale.

## Avvio rapido

```bash
npm install
npm run dev
```

Apri http://localhost:5173

## Configurazione backend

Di default punta a `localhost:8000` (proxy Vite).
Per un backend su altro host, crea `.env` (vedi `.env.example`):

```
VITE_API_URL=http://192.168.1.100:8000
VITE_WS_URL=ws://192.168.1.100:8000
```

`VITE_SHOW_DEMO_USERS=true` mostra gli account demo nella pagina di accesso anche nella build di produzione.

## Build produzione

```bash
npm run build
# output in dist/
```

Con Docker la build e nginx sono già configurati (`Dockerfile`, `nginx.conf`):

```bash
docker compose up -d --build dashboard
```

## Profili

| Profilo | Cosa mostra |
|---|---|
| Polizia Locale | Pratiche di sicurezza: elenco, mappa, dettaglio con eventi e attivazioni, escalation |
| Operatore Eco | Cestini da svuotare e segnalazioni sull'umidità del terreno |
| Manutenzione | Stato dei dispositivi, registro degli interventi, mappa |
| Modellino | Stato del modellino, andamento ambiente, allarmi e clip, soglie, simulazioni |
| Amministrazione | Panoramica, tutte le pratiche, dispositivi, energia, server (CPU, disco, pulizia delle clip), registrazione, sicurezza, accessi |

Gli amministratori possono passare da un profilo all'altro dal menu utente.

## Struttura

```
src/
  App.jsx                 accesso, scelta del profilo, sessione scaduta
  lib/api.js              chiamate al backend, WebSocket con riconnessione
  lib/map.js              mappa Leaflet condivisa
  lib/sound.js            avvisi sonori
  components/ui.jsx       componenti condivisi (pulsanti, dialog, tab, etichette)
  components/devices.jsx  etichette e stato dei dispositivi
  components/*Dashboard.jsx   una dashboard per profilo
```

Aggiornamenti in tempo reale: WebSocket `/practices/ws` per le pratiche, SSE `/mini/stream` per il modellino.
