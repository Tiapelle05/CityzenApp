import datetime as dt
from pydantic import BaseModel, model_serializer
from app.db.models import TypeEvent

class EventBase(BaseModel):
    mac_address: str | None = None  # nullo per gli eventi 'citizen'
    type: TypeEvent

class EventCreate(EventBase):
    pass

class EventCreateFromDevice(BaseModel):
    type: TypeEvent
    sampling_time: dt.datetime | None = None

class EventUpdate(BaseModel):
    type: TypeEvent | None = None

class EventInDBBase(EventBase):
    id: int
    val_number: float | None = None
    sampling_time: dt.datetime | None = None
    transmission_time: dt.datetime | None = None

    model_config = {"from_attributes": True}

class EventVideoBase(BaseModel):
    video_url: str
    thumbnail_url: str | None = None
    duration_seconds: int | None = None

class EventVideoCreate(EventVideoBase):
    pass

class EventVideo(EventVideoBase):
    id: int
    id_event: int
    created_at: dt.datetime

    model_config = {"from_attributes": True}

class Event(EventInDBBase):
    """
    Schema di risposta per gli eventi.
    - Eventi NON-alert: restituisce type, val_number, timestamp, ecc.
    - Eventi alert: restituisce type, dati video, timestamp (senza val_number).
    """
    video: EventVideo | None = None

    @model_serializer
    def serialize_model(self):
        base = {
            "id": self.id,
            "mac_address": self.mac_address,
            "type": self.type,
            "sampling_time": self.sampling_time,
            "transmission_time": self.transmission_time,
        }

        if self.type == TypeEvent.alert:
            # Per gli alert: mostra i dati del video, ometti val_number
            base["video"] = self.video.model_dump() if self.video else None
        else:
            # Per tutti gli altri: mostra val_number, ometti video
            base["val_number"] = self.val_number

        return base
