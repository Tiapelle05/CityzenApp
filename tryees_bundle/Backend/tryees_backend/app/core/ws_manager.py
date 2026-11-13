import asyncio, json, logging
from typing import List
from fastapi import WebSocket
logger = logging.getLogger(__name__)

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self._loop = None
    def set_loop(self, loop): self._loop = loop
    async def connect(self, ws):
        await ws.accept(); self.active_connections.append(ws)
    def disconnect(self, ws):
        if ws in self.active_connections: self.active_connections.remove(ws)
    async def broadcast(self, message):
        payload = json.dumps(message, default=str)
        dead = []
        for ws in self.active_connections:
            try: await ws.send_text(payload)
            except: dead.append(ws)
        for ws in dead: self.disconnect(ws)
    def broadcast_from_thread(self, message):
        if self._loop is None or not self.active_connections: return
        asyncio.run_coroutine_threadsafe(self.broadcast(message), self._loop)

ws_manager = ConnectionManager()
