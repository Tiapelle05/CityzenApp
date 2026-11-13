"""WebSocket dell'app del cittadino (/citizen/ws). Separato da ws_manager (dashboard
operatori): un messaggio per gli operatori non può arrivare a un cittadino nemmeno
per errore, e qui si può scrivere al singolo cittadino."""
import asyncio, json, logging
from collections import defaultdict
from fastapi import WebSocket

logger = logging.getLogger(__name__)

# Più dispositivi o riconnessioni dello stesso cittadino; oltre si chiude la più vecchia
MAX_CONNECTIONS_PER_CITIZEN = 5


class CitizenConnectionManager:
    def __init__(self):
        self._connections: dict[int, list[WebSocket]] = defaultdict(list)
        self._loop = None

    def set_loop(self, loop): self._loop = loop

    async def connect(self, citizen_id: int, ws: WebSocket):
        await ws.accept()
        conns = self._connections[citizen_id]
        conns.append(ws)
        while len(conns) > MAX_CONNECTIONS_PER_CITIZEN:
            oldest = conns.pop(0)
            try: await oldest.close(code=1000)
            except Exception: pass

    def disconnect(self, citizen_id: int, ws: WebSocket):
        conns = self._connections.get(citizen_id)
        if conns and ws in conns:
            conns.remove(ws)
        if not conns:
            self._connections.pop(citizen_id, None)

    async def _send(self, citizen_id: int, payload: str):
        for ws in list(self._connections.get(citizen_id, [])):
            try: await ws.send_text(payload)
            except Exception: self.disconnect(citizen_id, ws)

    async def send_to_citizen(self, citizen_id: int, message: dict):
        await self._send(citizen_id, json.dumps(message, default=str))

    async def broadcast(self, message: dict):
        """A tutti i cittadini connessi: i messaggi del parco portano park_id e l'app filtra sul suo."""
        payload = json.dumps(message, default=str)
        for citizen_id in list(self._connections):
            await self._send(citizen_id, payload)

    # Gli endpoint sincroni girano nel threadpool: si passa dall'event loop
    def send_to_citizen_from_thread(self, citizen_id: int, message: dict):
        if self._loop is None or citizen_id not in self._connections: return
        asyncio.run_coroutine_threadsafe(self.send_to_citizen(citizen_id, message), self._loop)

    def broadcast_from_thread(self, message: dict):
        if self._loop is None or not self._connections: return
        asyncio.run_coroutine_threadsafe(self.broadcast(message), self._loop)


citizen_ws_manager = CitizenConnectionManager()
