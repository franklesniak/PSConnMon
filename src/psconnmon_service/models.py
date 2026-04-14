"""Data contracts shared by the PSConnMon reporting service."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any, Callable

if TYPE_CHECKING:
    from pydantic import BaseModel, ConfigDict, Field, field_validator

    PYDANTIC_V2 = True
else:
    try:
        from pydantic import BaseModel, ConfigDict, Field, field_validator

        PYDANTIC_V2 = True
    except ImportError:  # pragma: no cover - compatibility path for local bootstrap
        from pydantic import BaseModel, Field, validator as _validator

        PYDANTIC_V2 = False

        def field_validator(*fields: str, **kwargs: object) -> Callable[[Callable[..., Any]], Any]:
            """Provide a Pydantic v2-style validator decorator on top of v1."""

            return _validator(*fields, **kwargs)


VALID_RESULTS = {"SUCCESS", "FAILURE", "TIMEOUT", "EMPTY", "SKIPPED", "FATAL", "INFO"}


class CompatBaseModel(BaseModel):
    """Compatibility helpers across Pydantic major versions."""

    if TYPE_CHECKING or PYDANTIC_V2:
        model_config = ConfigDict(populate_by_name=True)

    if not TYPE_CHECKING and not PYDANTIC_V2:

        class Config:
            allow_population_by_field_name = True

        @classmethod
        def model_validate(cls, obj: object) -> Any:
            return cls.parse_obj(obj)

        def model_dump(self, mode: str = "python", **kwargs: object) -> dict[str, Any]:
            return self.dict(**kwargs)

        def model_dump_json(self, **kwargs: object) -> str:
            return self.json(**kwargs)


class EventRecord(CompatBaseModel):
    """Structured PSConnMon event produced by the PowerShell agent."""

    if TYPE_CHECKING or PYDANTIC_V2:
        model_config = ConfigDict(extra="allow")

    if not TYPE_CHECKING and not PYDANTIC_V2:

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
    details: str
    dns_server: str | None = Field(default=None, alias="dnsServer")
    hop_index: int | None = Field(default=None, alias="hopIndex")
    hop_address: str | None = Field(default=None, alias="hopAddress")
    hop_name: str | None = Field(default=None, alias="hopName")
    hop_latency_ms: float | None = Field(default=None, alias="hopLatencyMs")
    path_hash: str | None = Field(default=None, alias="pathHash")
    metadata: dict[str, Any]

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
    total_agents: int
    total_targets: int
    active_sites: int
    failure_events: int
    timeout_events: int
    latest_timestamp_utc: datetime | None


class TargetSummary(CompatBaseModel):
    """Aggregated state for one target."""

    target_key: str = Field(alias="targetKey")
    target_id: str
    target_kind: str = Field(alias="targetKind")
    agent_id: str
    fqdn: str
    site_id: str
    target_address: str
    latest_result: str
    last_test_type: str
    last_latency_ms: float | None
    last_timestamp_utc: datetime | None


class PathSummary(CompatBaseModel):
    """Traceroute/path-change summary for one target."""

    target_key: str = Field(alias="targetKey")
    target_id: str
    target_kind: str = Field(alias="targetKind")
    fqdn: str
    path_hash: str
    path_preview: str = Field(alias="pathPreview")
    last_seen_utc: datetime | None
    hop_count: int
    average_hop_latency_ms: float | None


class IncidentSummary(CompatBaseModel):
    """Failure summary for the dashboard incident list."""

    target_key: str = Field(alias="targetKey")
    target_id: str
    fqdn: str
    test_type: str
    result: str
    error_code: str | None
    details: str
    timestamp_utc: datetime


class AgentSummary(CompatBaseModel):
    """Current reporting state for one deployed agent."""

    agent_id: str
    site_id: str
    total_targets: int
    healthy_targets: int
    failing_targets: int
    timeout_targets: int
    average_latency_ms: float | None
    last_timestamp_utc: datetime | None


class SiteSummary(CompatBaseModel):
    """Aggregated current state for one site."""

    site_id: str
    agent_count: int
    target_count: int
    failing_targets: int
    average_latency_ms: float | None
    last_timestamp_utc: datetime | None


class LatencyPoint(CompatBaseModel):
    """One point in a target latency timeline."""

    timestamp_utc: datetime
    latency_ms: float | None
    result: str
    test_type: str


class PathChangeSummary(CompatBaseModel):
    """A detected traceroute path transition for one target."""

    target_key: str = Field(alias="targetKey")
    target_id: str
    target_kind: str = Field(alias="targetKind")
    fqdn: str
    site_id: str
    agent_id: str
    previous_path_hash: str
    previous_path_preview: str = Field(alias="previousPathPreview")
    path_hash: str
    path_preview: str = Field(alias="pathPreview")
    hop_count: int
    timestamp_utc: datetime


class TestSummary(CompatBaseModel):
    """Current state summary for one test assigned to a target."""

    test_type: str
    latest_result: str
    latest_probe_name: str = Field(alias="latestProbeName")
    latest_target_address: str = Field(alias="latestTargetAddress")
    last_latency_ms: float | None = Field(alias="lastLatencyMs")
    last_timestamp_utc: datetime | None = Field(alias="lastTimestampUtc")
    event_count: int = Field(alias="eventCount")


class TargetEventSummary(CompatBaseModel):
    """Recent event record used for target drilldown rendering."""

    timestamp_utc: datetime = Field(alias="timestampUtc")
    test_type: str = Field(alias="testType")
    probe_name: str = Field(alias="probeName")
    result: str
    target_address: str = Field(alias="targetAddress")
    latency_ms: float | None = Field(default=None, alias="latencyMs")
    error_code: str | None = Field(default=None, alias="errorCode")
    details: str = ""
    dns_server: str | None = Field(default=None, alias="dnsServer")
    path_hash: str | None = Field(default=None, alias="pathHash")
    hop_index: int | None = Field(default=None, alias="hopIndex")
    hop_address: str | None = Field(default=None, alias="hopAddress")
    metadata: dict[str, Any] = Field(default_factory=dict)


class TargetDetail(CompatBaseModel):
    """Detailed drilldown payload for one target."""

    target: TargetSummary
    tests: list[TestSummary]
    recent_events: list[TargetEventSummary] = Field(alias="recentEvents")
    latency_series: list[LatencyPoint]
    incidents: list[IncidentSummary]
    paths: list[PathSummary]


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
    cumulative_discovered: int
    cumulative_imported: int
    cumulative_skipped: int
    cumulative_failed: int
    sources: list[ImportSourceStatus]


class DashboardSnapshot(CompatBaseModel):
    """Single payload used by the live dashboard client."""

    summary: FleetSummary
    agents: list[AgentSummary]
    sites: list[SiteSummary]
    targets: list[TargetSummary]
    paths: list[PathSummary]
    path_changes: list[PathChangeSummary]
    incidents: list[IncidentSummary]
    import_status: ImportStatus = Field(alias="importStatus")
    refreshed_utc: datetime = Field(alias="refreshedUtc")
