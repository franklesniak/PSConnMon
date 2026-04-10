"""DuckDB-backed storage for PSConnMon events and import status."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

import duckdb

from .models import (
    EventRecord,
    FleetSummary,
    ImportSourceStatus,
    ImportStatus,
    IncidentSummary,
    PathSummary,
    TargetSummary,
)


class StorageRepository:
    """Persist and query PSConnMon events using DuckDB."""

    def __init__(self, database_path: Path | str) -> None:
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> duckdb.DuckDBPyConnection:
        return duckdb.connect(str(self.database_path))

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.execute("""
                CREATE TABLE IF NOT EXISTS events (
                    timestamp_utc TIMESTAMP,
                    agent_id TEXT,
                    site_id TEXT,
                    target_id TEXT,
                    fqdn TEXT,
                    target_address TEXT,
                    test_type TEXT,
                    probe_name TEXT,
                    result TEXT,
                    latency_ms DOUBLE,
                    loss DOUBLE,
                    error_code TEXT,
                    details TEXT,
                    dns_server TEXT,
                    hop_index INTEGER,
                    hop_address TEXT,
                    hop_name TEXT,
                    hop_latency_ms DOUBLE,
                    path_hash TEXT,
                    metadata JSON
                )
                """)
            connection.execute("""
                CREATE TABLE IF NOT EXISTS import_ledger (
                    source_type TEXT,
                    source_identifier TEXT,
                    fingerprint TEXT,
                    imported_utc TIMESTAMP,
                    event_count INTEGER,
                    PRIMARY KEY (source_type, source_identifier, fingerprint)
                )
                """)
            connection.execute("""
                CREATE TABLE IF NOT EXISTS import_source_status (
                    source_type TEXT PRIMARY KEY,
                    last_run_utc TIMESTAMP,
                    last_success_utc TIMESTAMP,
                    last_error TEXT,
                    last_imported_batch_utc TIMESTAMP,
                    last_source_identifier TEXT,
                    last_run_discovered INTEGER NOT NULL DEFAULT 0,
                    last_run_imported INTEGER NOT NULL DEFAULT 0,
                    last_run_skipped INTEGER NOT NULL DEFAULT 0,
                    last_run_failed INTEGER NOT NULL DEFAULT 0,
                    last_run_backlog INTEGER NOT NULL DEFAULT 0,
                    cumulative_discovered BIGINT NOT NULL DEFAULT 0,
                    cumulative_imported BIGINT NOT NULL DEFAULT 0,
                    cumulative_skipped BIGINT NOT NULL DEFAULT 0,
                    cumulative_failed BIGINT NOT NULL DEFAULT 0
                )
                """)

    def ingest_events(self, events: list[EventRecord]) -> int:
        """Insert validated events into storage."""

        rows = [self._event_to_row(event) for event in events]
        with self._connect() as connection:
            connection.executemany(
                """
                INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                rows,
            )
        return len(rows)

    def ingest_import_batch(
        self,
        *,
        source_type: str,
        source_identifier: str,
        fingerprint: str,
        events: list[EventRecord],
    ) -> int:
        """Insert one imported batch and record it in the idempotency ledger."""

        rows = [self._event_to_row(event) for event in events]
        with self._connect() as connection:
            connection.execute("BEGIN TRANSACTION")
            try:
                connection.executemany(
                    """
                    INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    rows,
                )
                connection.execute(
                    """
                    INSERT INTO import_ledger VALUES (?, ?, ?, CURRENT_TIMESTAMP, ?)
                    """,
                    [source_type, source_identifier, fingerprint, len(rows)],
                )
                connection.execute("COMMIT")
            except Exception:
                connection.execute("ROLLBACK")
                raise

        return len(rows)

    def has_import_fingerprint(
        self, *, source_type: str, source_identifier: str, fingerprint: str
    ) -> bool:
        """Return True when the batch has already been imported."""

        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT 1
                FROM import_ledger
                WHERE source_type = ? AND source_identifier = ? AND fingerprint = ?
                LIMIT 1
                """,
                [source_type, source_identifier, fingerprint],
            ).fetchone()

        return row is not None

    def get_last_imported_batch_time(self, *, source_type: str) -> datetime | None:
        """Return the latest successful batch import time for one source."""

        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT MAX(imported_utc)
                FROM import_ledger
                WHERE source_type = ?
                """,
                [source_type],
            ).fetchone()

        return self._normalize_optional_timestamp(row[0] if row else None)

    def record_import_source_status(
        self,
        *,
        source_type: str,
        discovered: int,
        imported: int,
        skipped: int,
        failed: int,
        backlog: int,
        last_error: str | None,
        last_source_identifier: str | None,
        mark_success: bool,
        last_imported_batch_utc: datetime | None,
    ) -> ImportSourceStatus:
        """Upsert source-level import status and cumulative counters."""

        previous = self.get_source_status(source_type)
        current_run = datetime.utcnow()
        previous_success = previous.last_success_utc if previous is not None else None
        last_success = current_run if mark_success else previous_success
        previous_last_import = previous.last_imported_batch_utc if previous is not None else None
        effective_last_import = last_imported_batch_utc or previous_last_import

        cumulative_discovered = discovered + (previous.cumulative_discovered if previous else 0)
        cumulative_imported = imported + (previous.cumulative_imported if previous else 0)
        cumulative_skipped = skipped + (previous.cumulative_skipped if previous else 0)
        cumulative_failed = failed + (previous.cumulative_failed if previous else 0)

        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO import_source_status VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (source_type) DO UPDATE SET
                    last_run_utc = excluded.last_run_utc,
                    last_success_utc = excluded.last_success_utc,
                    last_error = excluded.last_error,
                    last_imported_batch_utc = excluded.last_imported_batch_utc,
                    last_source_identifier = excluded.last_source_identifier,
                    last_run_discovered = excluded.last_run_discovered,
                    last_run_imported = excluded.last_run_imported,
                    last_run_skipped = excluded.last_run_skipped,
                    last_run_failed = excluded.last_run_failed,
                    last_run_backlog = excluded.last_run_backlog,
                    cumulative_discovered = excluded.cumulative_discovered,
                    cumulative_imported = excluded.cumulative_imported,
                    cumulative_skipped = excluded.cumulative_skipped,
                    cumulative_failed = excluded.cumulative_failed
                """,
                [
                    source_type,
                    current_run,
                    last_success,
                    last_error,
                    effective_last_import,
                    last_source_identifier,
                    discovered,
                    imported,
                    skipped,
                    failed,
                    backlog,
                    cumulative_discovered,
                    cumulative_imported,
                    cumulative_skipped,
                    cumulative_failed,
                ],
            )

        source_status = self.get_source_status(source_type)
        if source_status is None:
            raise ValueError(f"Failed to persist import source status for '{source_type}'.")
        return source_status

    def get_source_status(self, source_type: str) -> ImportSourceStatus | None:
        """Return persisted status for one import source."""

        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT
                    source_type,
                    last_run_utc,
                    last_success_utc,
                    last_error,
                    last_imported_batch_utc,
                    last_source_identifier,
                    last_run_discovered,
                    last_run_imported,
                    last_run_skipped,
                    last_run_failed,
                    last_run_backlog,
                    cumulative_discovered,
                    cumulative_imported,
                    cumulative_skipped,
                    cumulative_failed
                FROM import_source_status
                WHERE source_type = ?
                """,
                [source_type],
            ).fetchone()

        return self._row_to_import_source_status(row)

    def get_import_status(self, mode: str) -> ImportStatus:
        """Return aggregate import status across all configured sources."""

        with self._connect() as connection:
            rows = connection.execute("""
                SELECT
                    source_type,
                    last_run_utc,
                    last_success_utc,
                    last_error,
                    last_imported_batch_utc,
                    last_source_identifier,
                    last_run_discovered,
                    last_run_imported,
                    last_run_skipped,
                    last_run_failed,
                    last_run_backlog,
                    cumulative_discovered,
                    cumulative_imported,
                    cumulative_skipped,
                    cumulative_failed
                FROM import_source_status
                ORDER BY source_type
                """).fetchall()

        sources = [
            status for status in (self._row_to_import_source_status(row) for row in rows) if status
        ]
        latest_error_source = max(
            (source for source in sources if source.last_error and source.last_run_utc is not None),
            default=None,
            key=lambda source: source.last_run_utc,
        )

        return ImportStatus(
            mode=mode,
            last_run_utc=max(
                (source.last_run_utc for source in sources if source.last_run_utc), default=None
            ),
            last_success_utc=max(
                (source.last_success_utc for source in sources if source.last_success_utc),
                default=None,
            ),
            last_error=latest_error_source.last_error if latest_error_source else None,
            discovered=sum(source.cumulative_discovered for source in sources),
            imported=sum(source.cumulative_imported for source in sources),
            skipped=sum(source.cumulative_skipped for source in sources),
            failed=sum(source.cumulative_failed for source in sources),
            sources=sources,
        )

    def get_fleet_summary(self) -> FleetSummary:
        """Return a one-row aggregated fleet summary."""

        with self._connect() as connection:
            row = connection.execute("""
                SELECT
                    COUNT(*) AS total_events,
                    COUNT(DISTINCT target_id) AS total_targets,
                    COUNT(DISTINCT site_id) AS active_sites,
                    SUM(CASE WHEN result IN ('FAILURE', 'FATAL') THEN 1 ELSE 0 END) AS failure_events,
                    SUM(CASE WHEN result = 'TIMEOUT' THEN 1 ELSE 0 END) AS timeout_events,
                    MAX(timestamp_utc) AS latest_timestamp_utc
                FROM events
                """).fetchone()

        return FleetSummary(
            total_events=int(row[0] or 0),
            total_targets=int(row[1] or 0),
            active_sites=int(row[2] or 0),
            failure_events=int(row[3] or 0),
            timeout_events=int(row[4] or 0),
            latest_timestamp_utc=row[5],
        )

    def list_targets(self) -> list[TargetSummary]:
        """Return current status per target."""

        query = """
            WITH ranked AS (
                SELECT
                    target_id,
                    fqdn,
                    site_id,
                    result,
                    latency_ms,
                    timestamp_utc,
                    ROW_NUMBER() OVER (PARTITION BY target_id ORDER BY timestamp_utc DESC) AS row_number
                FROM events
            )
            SELECT target_id, fqdn, site_id, result, latency_ms, timestamp_utc
            FROM ranked
            WHERE row_number = 1
            ORDER BY fqdn
        """

        with self._connect() as connection:
            rows = connection.execute(query).fetchall()

        return [
            TargetSummary(
                target_id=row[0],
                fqdn=row[1],
                site_id=row[2],
                latest_result=row[3],
                last_latency_ms=row[4],
                last_timestamp_utc=row[5],
            )
            for row in rows
        ]

    def list_paths(self) -> list[PathSummary]:
        """Return traceroute/path summaries."""

        query = """
            SELECT
                target_id,
                fqdn,
                COALESCE(path_hash, 'unknown') AS path_hash,
                MAX(timestamp_utc) AS last_seen_utc,
                COUNT(DISTINCT hop_index) AS hop_count,
                AVG(hop_latency_ms) AS average_hop_latency_ms
            FROM events
            WHERE test_type = 'traceroute'
            GROUP BY target_id, fqdn, COALESCE(path_hash, 'unknown')
            ORDER BY fqdn, last_seen_utc DESC
        """

        with self._connect() as connection:
            rows = connection.execute(query).fetchall()

        return [
            PathSummary(
                target_id=row[0],
                fqdn=row[1],
                path_hash=row[2],
                last_seen_utc=row[3],
                hop_count=int(row[4] or 0),
                average_hop_latency_ms=row[5],
            )
            for row in rows
        ]

    def list_incidents(self, limit: int = 25) -> list[IncidentSummary]:
        """Return recent non-success events."""

        query = """
            SELECT
                target_id,
                fqdn,
                test_type,
                result,
                error_code,
                details,
                timestamp_utc
            FROM events
            WHERE result NOT IN ('SUCCESS', 'INFO')
            ORDER BY timestamp_utc DESC
            LIMIT ?
        """

        with self._connect() as connection:
            rows = connection.execute(query, [limit]).fetchall()

        return [
            IncidentSummary(
                target_id=row[0],
                fqdn=row[1],
                test_type=row[2],
                result=row[3],
                error_code=row[4],
                details=row[5],
                timestamp_utc=self._normalize_timestamp(row[6]),
            )
            for row in rows
        ]

    @staticmethod
    def _event_to_row(event: EventRecord) -> tuple[object, ...]:
        """Convert one event model into the storage row shape."""

        return (
            event.timestamp_utc,
            event.agent_id,
            event.site_id,
            event.target_id,
            event.fqdn,
            event.target_address,
            event.test_type,
            event.probe_name,
            event.result,
            event.latency_ms,
            event.loss,
            event.error_code,
            event.details,
            event.dns_server,
            event.hop_index,
            event.hop_address,
            event.hop_name,
            event.hop_latency_ms,
            event.path_hash,
            event.model_dump_json(include={"metadata"}),
        )

    def _row_to_import_source_status(
        self, row: tuple[object, ...] | None
    ) -> ImportSourceStatus | None:
        """Convert a raw DuckDB row into an import source status model."""

        if row is None:
            return None

        return ImportSourceStatus(
            source_type=str(row[0]),
            last_run_utc=self._normalize_optional_timestamp(row[1]),
            last_success_utc=self._normalize_optional_timestamp(row[2]),
            last_error=str(row[3]) if row[3] is not None else None,
            last_imported_batch_utc=self._normalize_optional_timestamp(row[4]),
            last_source_identifier=str(row[5]) if row[5] is not None else None,
            last_run_discovered=int(row[6] or 0),
            last_run_imported=int(row[7] or 0),
            last_run_skipped=int(row[8] or 0),
            last_run_failed=int(row[9] or 0),
            last_run_backlog=int(row[10] or 0),
            cumulative_discovered=int(row[11] or 0),
            cumulative_imported=int(row[12] or 0),
            cumulative_skipped=int(row[13] or 0),
            cumulative_failed=int(row[14] or 0),
        )

    @staticmethod
    def _normalize_timestamp(value: datetime | None) -> datetime:
        """DuckDB may return naive UTC timestamps; normalize for API output."""

        if value is None:
            raise ValueError("Incident timestamp must not be null.")
        return value

    @staticmethod
    def _normalize_optional_timestamp(value: object) -> datetime | None:
        """Normalize optional timestamps returned by DuckDB."""

        if value is None:
            return None
        return value  # type: ignore[return-value]
