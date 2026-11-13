"""Schemi delle API /citizen. I formati seguono gli esempi JSON del brief
tecnico per il team Flutter: non vanno cambiati senza avvisarli."""
import datetime as dt
from typing import Literal
from pydantic import BaseModel, Field, UUID4

ReportKind   = Literal["problem", "suggestion", "feedback"]
ReportStatus = Literal["received", "in_progress", "resolved", "closed"]


class CitizenRegister(BaseModel):
    install_id: UUID4 = Field(description="UUID v4 generato dall'app al primo avvio")
    platform: Literal["android", "ios", "web"]
    app_version: str = Field(min_length=1, max_length=32)


class CitizenSession(BaseModel):
    citizen_id: str
    access_token: str
    token_type: str = "bearer"
    expires_in: int = Field(description="Durata del token in secondi")


class CitizenPark(BaseModel):
    id: int
    name: str
    city: str
    lat: float | None = None
    lon: float | None = None


class ParkHighlight(BaseModel):
    category: str
    label: str
    count: int


class ParkStatus(BaseModel):
    park_id: int
    level: Literal["ok", "warning", "alert"]
    message: str
    open_issues: int
    updated_at: dt.datetime
    highlights: list[ParkHighlight]


class ParkNoticeOut(BaseModel):
    id: int
    title: str
    body: str
    level: Literal["info", "warning", "alert"]
    starts_at: dt.datetime
    ends_at: dt.datetime | None = None


class CitizenCategoryOut(BaseModel):
    code: str
    label: str
    icon: str | None = None
    kinds: list[ReportKind]


class ReportCreated(BaseModel):
    id: int
    code: str = Field(examples=["SEG-2026-000431"])
    kind: ReportKind
    status: ReportStatus
    status_label: str
    created_at: dt.datetime
    photo_url: str | None = None


class ReportSummary(BaseModel):
    id: int
    code: str
    kind: ReportKind
    category: str | None = None
    summary: str
    status: ReportStatus
    status_label: str
    created_at: dt.datetime
    updated_at: dt.datetime


class ReportPage(BaseModel):
    items: list[ReportSummary]
    total: int


class ReportHistoryItem(BaseModel):
    status: ReportStatus
    at: dt.datetime
    note: str | None = None


class ReportDetail(ReportSummary):
    description: str
    priority: Literal["low", "medium", "high"] | None = None
    lat: float | None = None
    lon: float | None = None
    rating: int | None = None
    photo_url: str | None = None
    history: list[ReportHistoryItem]


class IdeaCreate(BaseModel):
    park_id: int
    title: str = Field(min_length=3, max_length=120)
    description: str = Field(min_length=10, max_length=1000)
    visibility: Literal["public", "private"] = "public"
    client_ref: UUID4 = Field(description="UUID v4 stabile per rendere idempotente l'invio")


class IdeaOut(BaseModel):
    id: int
    code: str
    title: str
    description: str
    visibility: Literal["public", "private"]
    vote_count: int
    voted_by_me: bool
    created_at: dt.datetime


class IdeaPage(BaseModel):
    items: list[IdeaOut]
    total: int


class IdeaVoteResult(BaseModel):
    idea_id: int
    vote_count: int
    voted_by_me: bool

