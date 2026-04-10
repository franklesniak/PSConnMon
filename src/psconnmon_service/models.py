"""Data contracts shared by the PSConnMon reporting service."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

try:
    from pydantic import BaseModel, ConfigDict, Field, field_validator

    PYDANTIC_V2 = True
except ImportError:  # pragma: no cover - compatibility path for local bootstrap
    from pydantic import BaseModel, Field, validator

    PYDANTIC_V2 = False
    ConfigDict = dict

    def field_validator(*fields: str, **kwargs: object):
        return validator(*fields, **kwargs)


VALID_RESULTS = {"SUCCESS", "FAILURE", "TIMEOUT", "EMPTY", "SKIPPED", "FATAL", "INFO"}


class CompatBaseModel(BaseModel):
    """Compatibility helpers across Pydantic major versions."""

    if not PYDANTIC_V2:

        @classmethod
        def model_validate(cls, obj: object):
            return cls.parse_obj(obj)

        def model_dump(self, mode: str = "python", **kwargs: object) -> dict[str, Any]:
            return self.dict(**kwargs)

        def model_dump_json(self, **kwargs: object) -> str:
            return self.json(**kwargs)


class EventRecord(CompatBaseModel):
    """Structured PSConnMon event produced by the PowerShell agent."""

    if PYDANTIC_V2:
        model_config = ConfigDict(extra="allow")

    if not PYDANTIC_V2:

        class Config:
            extra = "allow"

    timestamp_utc: datetime = Field(alias="timestampUtc")
    agent_id: str = Field(alias="agentId", min_length=1)
    site_id: str = Field(alias="siteId", min_length=1)
    target_id: str = Field(alias="targetId", min_length=1)
    fqdn: str = Field(min_length=1)
    target_address: str = Field(alias="targetAddress", min_length=1)
    test_type: str = Field(alias="testType", min_length=1)
    probe_name: str = Field(alias="probeName", min_length=1)
    result: str = Field(min_length=1)
    latency_ms: float | None = Field(default=None, alias="latencyMs")
    loss: float | None = None
    error_code: str | None = Field(default=None, alias="errorCode")
    details: str = ""
    dns_server: str | None = Field(default=None, alias="dnsServer")
    hop_index: int | None = Field(default=None, alias="hopIndex")
    hop_address: str | None = Field(default=None, alias="hopAddress")
    hop_name: str | None = Field(default=None, alias="hopName")
    hop_latency_ms: float | None = Field(default=None, alias="hopLatencyMs")
    path_hash: str | None = Field(default=None, alias="pathHash")
    metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("timestamp_utc")
    @classmethod
    def validate_timestamp(cls, value: datetime) -> datetime:
        """Normalize timestamps to timezone-aware UTC values."""

        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    @field_validator("result")
    @classmethod
    def validate_result(cls, value: str) -> str:
        """Reject unsupported result states."""

        if value not in VALID_RESULTS:
            raise ValueError(f"Unsupported result: {value}")
        return value


class IngestBatch(CompatBaseModel):
    """Batch ingest payload for API uploads."""

    events: list[EventRecord]

    @field_validator("events")
    @classmethod
    def validate_events(cls, value: list[EventRecord]) -> list[EventRecord]:
        """Require at least one event in each batch."""

        if len(value) < 1:
            raise ValueError("At least one event is required.")
        return value


class FleetSummary(CompatBaseModel):
    """Aggregated service-level summary for dashboard rendering."""

    total_events: int
    total_targets: int
    active_sites: int
    failure_events: int
    timeout_events: int
    latest_timestamp_utc: datetime | None


class TargetSummary(CompatBaseModel):
    """Aggregated state for one target."""

    target_id: str
    fqdn: str
    site_id: str
    latest_result: str
    last_latency_ms: float | None
    last_timestamp_utc: datetime | None


class PathSummary(CompatBaseModel):
    """Traceroute/path-change summary for one target."""

    target_id: str
    fqdn: str
    path_hash: str
    last_seen_utc: datetime | None
    hop_count: int
    average_hop_latency_ms: float | None


class IncidentSummary(CompatBaseModel):
    """Failure summary for the dashboard incident list."""

    target_id: str
    fqdn: str
    test_type: str
    result: str
    error_code: str | None
    details: str
    timestamp_utc: datetime


class ImportSourceStatus(CompatBaseModel):
    """Per-source import state persisted by the reporting service."""

    source_type: str
    last_run_utc: datetime | None
    last_success_utc: datetime | None
    last_error: str | None
    last_imported_batch_utc: datetime | None
    last_source_identifier: str | None
    last_run_discovered: int
    last_run_imported: int
    last_run_skipped: int
    last_run_failed: int
    last_run_backlog: int
    cumulative_discovered: int
    cumulative_imported: int
    cumulative_skipped: int
    cumulative_failed: int


class ImportStatus(CompatBaseModel):
    """Aggregated import status for the dashboard and API."""

    mode: str
    last_run_utc: datetime | None
    last_success_utc: datetime | None
    last_error: str | None
    discovered: int
    imported: int
    skipped: int
    failed: int
    sources: list[ImportSourceStatus]
