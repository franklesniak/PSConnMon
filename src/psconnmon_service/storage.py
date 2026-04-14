"""DuckDB-backed storage for PSConnMon events and import status."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, TypeVar, cast

import duckdb

from .models import (
    AgentSummary,
    CompatBaseModel,
    EventRecord,
    FleetSummary,
    ImportSourceStatus,
    ImportStatus,
    IncidentSummary,
    LatencyPoint,
    PathSummary,
    PathChangeSummary,
    SiteSummary,
    TargetDetail,
    TargetEventSummary,
    TargetSummary,
    TestSummary,
)

TModel = TypeVar("TModel", bound=CompatBaseModel)


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
            key=lambda source: source.last_run_utc or datetime.min.replace(tzinfo=timezone.utc),
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

    def get_fleet_summary(self, window_minutes: int | None = None) -> FleetSummary:
        """Return a one-row aggregated fleet summary."""

        where_clause = ""
        parameters: list[object] = []
        if window_minutes is not None:
            window_start = datetime.utcnow() - timedelta(minutes=window_minutes)
            where_clause = "WHERE timestamp_utc >= ?"
            parameters.append(window_start)

        with self._connect() as connection:
            row = connection.execute(
                f"""
                SELECT
                    COUNT(*) AS total_events,
                    COUNT(DISTINCT agent_id) AS total_agents,
                    COUNT(DISTINCT agent_id || '::' || target_id) AS total_targets,
                    COUNT(DISTINCT site_id) AS active_sites,
                    SUM(CASE WHEN result IN ('FAILURE', 'FATAL') THEN 1 ELSE 0 END) AS failure_events,
                    SUM(CASE WHEN result = 'TIMEOUT' THEN 1 ELSE 0 END) AS timeout_events,
                    MAX(timestamp_utc) AS latest_timestamp_utc
                FROM events
                {where_clause}
                """,
                parameters,
            ).fetchone()

        if row is None:
            return FleetSummary(
                total_events=0,
                total_agents=0,
                total_targets=0,
                active_sites=0,
                failure_events=0,
                timeout_events=0,
                latest_timestamp_utc=None,
            )

        return FleetSummary(
            total_events=int(row[0] or 0),
            total_agents=int(row[1] or 0),
            total_targets=int(row[2] or 0),
            active_sites=int(row[3] or 0),
            failure_events=int(row[4] or 0),
            timeout_events=int(row[5] or 0),
            latest_timestamp_utc=self._normalize_optional_timestamp(row[6]),
        )

    def list_targets(self) -> list[TargetSummary]:
        """Return current status per target."""

        query = """
            WITH latest_target_state AS (
                SELECT
                    agent_id || '::' || target_id AS target_key,
                    target_id,
                    COALESCE(
                        json_extract_string(metadata, '$.targetKind'),
                        CASE
                            WHEN target_id LIKE 'internet-%' THEN 'external'
                            ELSE 'internal'
                        END
                    ) AS target_kind,
                    agent_id,
                    fqdn,
                    site_id,
                    target_address,
                    test_type,
                    result,
                    timestamp_utc,
                    ROW_NUMBER() OVER (
                        PARTITION BY agent_id, target_id
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE result <> 'INFO'
            ),
            latest_latency AS (
                SELECT
                    agent_id,
                    target_id,
                    latency_ms,
                    ROW_NUMBER() OVER (
                        PARTITION BY agent_id, target_id
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE result <> 'INFO' AND latency_ms IS NOT NULL
            )
            SELECT
                state.target_key,
                state.target_id,
                state.target_kind,
                state.agent_id,
                state.fqdn,
                state.site_id,
                state.target_address,
                state.test_type,
                state.result,
                latency.latency_ms,
                state.timestamp_utc
            FROM latest_target_state AS state
            LEFT JOIN latest_latency AS latency
                ON latency.agent_id = state.agent_id
               AND latency.target_id = state.target_id
               AND latency.row_number = 1
            WHERE state.row_number = 1
            ORDER BY state.target_kind, state.fqdn, state.agent_id
        """

        with self._connect() as connection:
            rows = connection.execute(query).fetchall()

        return [
            self._build_model(
                TargetSummary,
                target_key=row[0],
                target_id=row[1],
                target_kind=row[2],
                agent_id=row[3],
                fqdn=row[4],
                site_id=row[5],
                target_address=row[6],
                last_test_type=row[7],
                latest_result=row[8],
                last_latency_ms=row[9],
                last_timestamp_utc=self._normalize_timestamp(row[10]),
            )
            for row in rows
        ]

    def list_agents(self) -> list[AgentSummary]:
        """Return current reporting state per agent."""

        query = """
            WITH latest_target_state AS (
                SELECT
                    agent_id,
                    site_id,
                    target_id,
                    result,
                    timestamp_utc,
                    ROW_NUMBER() OVER (
                        PARTITION BY agent_id, target_id
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE result <> 'INFO'
            ),
            latest_target_latency AS (
                SELECT
                    agent_id,
                    target_id,
                    latency_ms,
                    ROW_NUMBER() OVER (
                        PARTITION BY agent_id, target_id
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE result <> 'INFO' AND latency_ms IS NOT NULL
            )
            SELECT
                state.agent_id,
                MAX(state.site_id) AS site_id,
                COUNT(*) AS total_targets,
                SUM(CASE WHEN state.result = 'SUCCESS' THEN 1 ELSE 0 END) AS healthy_targets,
                SUM(CASE WHEN state.result IN ('FAILURE', 'FATAL') THEN 1 ELSE 0 END) AS failing_targets,
                SUM(CASE WHEN state.result = 'TIMEOUT' THEN 1 ELSE 0 END) AS timeout_targets,
                AVG(latency.latency_ms) AS average_latency_ms,
                MAX(state.timestamp_utc) AS last_timestamp_utc
            FROM latest_target_state AS state
            LEFT JOIN latest_target_latency AS latency
                ON latency.agent_id = state.agent_id
               AND latency.target_id = state.target_id
               AND latency.row_number = 1
            WHERE state.row_number = 1
            GROUP BY state.agent_id
            ORDER BY last_timestamp_utc DESC, state.agent_id
        """

        with self._connect() as connection:
            rows = connection.execute(query).fetchall()

        return [
            AgentSummary(
                agent_id=row[0],
                site_id=row[1],
                total_targets=int(row[2] or 0),
                healthy_targets=int(row[3] or 0),
                failing_targets=int(row[4] or 0),
                timeout_targets=int(row[5] or 0),
                average_latency_ms=row[6],
                last_timestamp_utc=self._normalize_timestamp(row[7]),
            )
            for row in rows
        ]

    def list_sites(self) -> list[SiteSummary]:
        """Return current reporting state per site."""

        query = """
            WITH latest_target_state AS (
                SELECT
                    site_id,
                    agent_id,
                    target_id,
                    result,
                    timestamp_utc,
                    ROW_NUMBER() OVER (
                        PARTITION BY site_id, agent_id, target_id
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE result <> 'INFO'
            ),
            latest_target_latency AS (
                SELECT
                    site_id,
                    agent_id,
                    target_id,
                    latency_ms,
                    ROW_NUMBER() OVER (
                        PARTITION BY site_id, agent_id, target_id
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE result <> 'INFO' AND latency_ms IS NOT NULL
            )
            SELECT
                state.site_id,
                COUNT(DISTINCT state.agent_id) AS agent_count,
                COUNT(*) AS target_count,
                SUM(CASE WHEN state.result IN ('FAILURE', 'FATAL', 'TIMEOUT') THEN 1 ELSE 0 END) AS failing_targets,
                AVG(latency.latency_ms) AS average_latency_ms,
                MAX(state.timestamp_utc) AS last_timestamp_utc
            FROM latest_target_state AS state
            LEFT JOIN latest_target_latency AS latency
                ON latency.site_id = state.site_id
               AND latency.agent_id = state.agent_id
               AND latency.target_id = state.target_id
               AND latency.row_number = 1
            WHERE state.row_number = 1
            GROUP BY state.site_id
            ORDER BY state.site_id
        """

        with self._connect() as connection:
            rows = connection.execute(query).fetchall()

        return [
            SiteSummary(
                site_id=row[0],
                agent_count=int(row[1] or 0),
                target_count=int(row[2] or 0),
                failing_targets=int(row[3] or 0),
                average_latency_ms=row[4],
                last_timestamp_utc=self._normalize_timestamp(row[5]),
            )
            for row in rows
        ]

    def list_paths(self) -> list[PathSummary]:
        """Return traceroute/path summaries."""

        query = """
            WITH latest_hops AS (
                SELECT
                    agent_id || '::' || target_id AS target_key,
                    target_id,
                    COALESCE(
                        json_extract_string(metadata, '$.targetKind'),
                        CASE
                            WHEN target_id LIKE 'internet-%' THEN 'external'
                            ELSE 'internal'
                        END
                    ) AS target_kind,
                    agent_id,
                    fqdn,
                    COALESCE(path_hash, 'unknown') AS path_hash,
                    hop_index,
                    COALESCE(hop_name, hop_address, '*') AS hop_label,
                    hop_latency_ms,
                    timestamp_utc,
                    ROW_NUMBER() OVER (
                        PARTITION BY agent_id, target_id, COALESCE(path_hash, 'unknown'), hop_index
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE test_type = 'traceroute' AND hop_index IS NOT NULL
            )
            SELECT
                target_key,
                target_id,
                target_kind,
                agent_id,
                fqdn,
                path_hash,
                string_agg(hop_label, ' -> ' ORDER BY hop_index) AS path_preview,
                MAX(timestamp_utc) AS last_seen_utc,
                COUNT(*) AS hop_count,
                AVG(hop_latency_ms) AS average_hop_latency_ms
            FROM latest_hops
            WHERE row_number = 1
            GROUP BY target_key, target_id, target_kind, agent_id, fqdn, path_hash
            ORDER BY target_kind, fqdn, agent_id, last_seen_utc DESC
        """

        with self._connect() as connection:
            rows = connection.execute(query).fetchall()

        return [
            self._build_model(
                PathSummary,
                target_key=row[0],
                target_id=row[1],
                target_kind=row[2],
                fqdn=row[4],
                path_hash=row[5],
                path_preview=row[6] or "",
                last_seen_utc=self._normalize_timestamp(row[7]),
                hop_count=int(row[8] or 0),
                average_hop_latency_ms=row[9],
            )
            for row in rows
        ]

    def list_incidents(self, limit: int = 25) -> list[IncidentSummary]:
        """Return recent non-success events."""

        query = """
            SELECT
                agent_id || '::' || target_id AS target_key,
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
            self._build_model(
                IncidentSummary,
                target_key=row[0],
                target_id=row[1],
                fqdn=row[2],
                test_type=row[3],
                result=row[4],
                error_code=row[5],
                details=row[6],
                timestamp_utc=self._normalize_timestamp(row[7]),
            )
            for row in rows
        ]

    def list_path_changes(self, limit: int = 25) -> list[PathChangeSummary]:
        """Return recent traceroute path transitions."""

        query = """
            WITH latest_hops AS (
                SELECT
                    agent_id || '::' || target_id AS target_key,
                    target_id,
                    COALESCE(
                        json_extract_string(metadata, '$.targetKind'),
                        CASE
                            WHEN target_id LIKE 'internet-%' THEN 'external'
                            ELSE 'internal'
                        END
                    ) AS target_kind,
                    fqdn,
                    site_id,
                    agent_id,
                    COALESCE(path_hash, 'unknown') AS path_hash,
                    hop_index,
                    COALESCE(hop_name, hop_address, '*') AS hop_label,
                    timestamp_utc,
                    ROW_NUMBER() OVER (
                        PARTITION BY agent_id, target_id, COALESCE(path_hash, 'unknown'), hop_index
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE test_type = 'traceroute' AND path_hash IS NOT NULL AND hop_index IS NOT NULL
            ),
            per_path AS (
                SELECT
                    target_key,
                    target_id,
                    target_kind,
                    fqdn,
                    site_id,
                    agent_id,
                    path_hash,
                    string_agg(hop_label, ' -> ' ORDER BY hop_index) AS path_preview,
                    MAX(timestamp_utc) AS timestamp_utc,
                    COUNT(*) AS hop_count
                FROM latest_hops
                WHERE row_number = 1
                GROUP BY target_key, target_id, target_kind, fqdn, site_id, agent_id, path_hash
            ),
            ordered AS (
                SELECT
                    target_key,
                target_id,
                target_kind,
                fqdn,
                site_id,
                agent_id,
                path_hash,
                path_preview,
                hop_count,
                timestamp_utc,
                    LAG(path_hash) OVER (
                        PARTITION BY target_key
                        ORDER BY timestamp_utc
                    ) AS previous_path_hash,
                    LAG(path_preview) OVER (
                        PARTITION BY target_key
                        ORDER BY timestamp_utc
                    ) AS previous_path_preview
                FROM per_path
            )
            SELECT
                target_key,
                target_id,
                target_kind,
                fqdn,
                site_id,
                agent_id,
                previous_path_hash,
                previous_path_preview,
                path_hash,
                path_preview,
                hop_count,
                timestamp_utc
            FROM ordered
            WHERE previous_path_hash IS NOT NULL AND previous_path_hash <> path_hash
            ORDER BY timestamp_utc DESC
            LIMIT ?
        """

        with self._connect() as connection:
            rows = connection.execute(query, [limit]).fetchall()

        return [
            self._build_model(
                PathChangeSummary,
                target_key=row[0],
                target_id=row[1],
                target_kind=row[2],
                fqdn=row[3],
                site_id=row[4],
                agent_id=row[5],
                previous_path_hash=row[6],
                previous_path_preview=row[7] or "",
                path_hash=row[8],
                path_preview=row[9] or "",
                hop_count=int(row[10] or 0),
                timestamp_utc=self._normalize_timestamp(row[11]),
            )
            for row in rows
        ]

    def get_target_detail(
        self,
        target_key: str,
        timeline_limit: int = 240,
        window_minutes: int | None = None,
    ) -> TargetDetail | None:
        """Return a detailed drilldown payload for one target."""

        agent_id, separator, target_id = target_key.partition("::")
        if not separator or not agent_id or not target_id:
            return None

        targets = [target for target in self.list_targets() if target.target_key == target_key]
        if not targets:
            return None

        time_filter = ""
        parameters_prefix: list[object] = [agent_id, target_id]
        if window_minutes is not None:
            window_start = datetime.utcnow() - timedelta(minutes=window_minutes)
            time_filter = " AND timestamp_utc >= ?"
            parameters_prefix.append(window_start)

        timeline_query = (
            """
            SELECT timestamp_utc, latency_ms, result, test_type
            FROM events
            WHERE agent_id = ? AND target_id = ? AND latency_ms IS NOT NULL
        """
            + time_filter
            + """
            ORDER BY timestamp_utc DESC
            LIMIT ?
        """
        )
        test_query = (
            """
            WITH ranked AS (
                SELECT
                    test_type,
                    probe_name,
                    result,
                    target_address,
                    latency_ms,
                    timestamp_utc,
                    COUNT(*) OVER (PARTITION BY test_type) AS event_count,
                    ROW_NUMBER() OVER (
                        PARTITION BY test_type
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE agent_id = ? AND target_id = ? AND result <> 'INFO'
        """
            + time_filter
            + """
            )
            SELECT
                test_type,
                result,
                probe_name,
                target_address,
                latency_ms,
                timestamp_utc,
                event_count
            FROM ranked
            WHERE row_number = 1
            ORDER BY test_type
        """
        )
        recent_event_query = (
            """
            SELECT
                timestamp_utc,
                test_type,
                probe_name,
                result,
                target_address,
                latency_ms,
                error_code,
                details,
                dns_server,
                path_hash,
                hop_index,
                hop_address,
                metadata
            FROM events
            WHERE agent_id = ? AND target_id = ?
        """
            + time_filter
            + """
            ORDER BY timestamp_utc DESC
            LIMIT 80
        """
        )
        path_query = (
            """
            WITH latest_hops AS (
                SELECT
                    agent_id || '::' || target_id AS target_key,
                    target_id,
                    COALESCE(
                        json_extract_string(metadata, '$.targetKind'),
                        CASE
                            WHEN target_id LIKE 'internet-%' THEN 'external'
                            ELSE 'internal'
                        END
                    ) AS target_kind,
                    fqdn,
                    COALESCE(path_hash, 'unknown') AS path_hash,
                    hop_index,
                    COALESCE(hop_name, hop_address, '*') AS hop_label,
                    hop_latency_ms,
                    timestamp_utc,
                    ROW_NUMBER() OVER (
                        PARTITION BY agent_id, target_id, COALESCE(path_hash, 'unknown'), hop_index
                        ORDER BY timestamp_utc DESC
                    ) AS row_number
                FROM events
                WHERE agent_id = ? AND target_id = ? AND test_type = 'traceroute' AND hop_index IS NOT NULL
        """
            + time_filter
            + """
            )
            SELECT
                target_key,
                target_id,
                target_kind,
                fqdn,
                path_hash,
                string_agg(hop_label, ' -> ' ORDER BY hop_index) AS path_preview,
                MAX(timestamp_utc) AS last_seen_utc,
                COUNT(*) AS hop_count,
                AVG(hop_latency_ms) AS average_hop_latency_ms
            FROM latest_hops
            WHERE row_number = 1
            GROUP BY target_key, target_id, target_kind, fqdn, path_hash
            ORDER BY last_seen_utc DESC
            LIMIT 8
        """
        )
        incident_query = (
            """
            SELECT
                target_id,
                fqdn,
                test_type,
                result,
                error_code,
                details,
                timestamp_utc
            FROM events
            WHERE agent_id = ? AND target_id = ? AND result NOT IN ('SUCCESS', 'INFO')
        """
            + time_filter
            + """
            ORDER BY timestamp_utc DESC
            LIMIT 12
        """
        )

        with self._connect() as connection:
            timeline_rows = connection.execute(
                timeline_query, [*parameters_prefix, timeline_limit]
            ).fetchall()
            test_rows = connection.execute(test_query, parameters_prefix).fetchall()
            recent_event_rows = connection.execute(recent_event_query, parameters_prefix).fetchall()
            path_rows = connection.execute(path_query, parameters_prefix).fetchall()
            incident_rows = connection.execute(incident_query, parameters_prefix).fetchall()

        return self._build_model(
            TargetDetail,
            target=targets[0],
            tests=[
                self._build_model(
                    TestSummary,
                    test_type=row[0],
                    latest_result=row[1],
                    latest_probe_name=row[2],
                    latest_target_address=row[3],
                    last_latency_ms=row[4],
                    last_timestamp_utc=self._normalize_optional_timestamp(row[5]),
                    event_count=int(row[6] or 0),
                )
                for row in test_rows
            ],
            recent_events=[
                self._build_model(
                    TargetEventSummary,
                    timestamp_utc=self._normalize_timestamp(row[0]),
                    test_type=row[1],
                    probe_name=row[2],
                    result=row[3],
                    target_address=row[4],
                    latency_ms=row[5],
                    error_code=row[6],
                    details=row[7],
                    dns_server=row[8],
                    path_hash=row[9],
                    hop_index=row[10],
                    hop_address=row[11],
                    metadata=self._normalize_metadata(row[12]),
                )
                for row in recent_event_rows
            ],
            latency_series=[
                LatencyPoint(
                    timestamp_utc=self._normalize_timestamp(row[0]),
                    latency_ms=row[1],
                    result=row[2],
                    test_type=row[3],
                )
                for row in reversed(timeline_rows)
            ],
            incidents=[
                self._build_model(
                    IncidentSummary,
                    target_key=f"{agent_id}::{row[0]}",
                    target_id=row[0],
                    fqdn=row[1],
                    test_type=row[2],
                    result=row[3],
                    error_code=row[4],
                    details=row[5],
                    timestamp_utc=self._normalize_timestamp(row[6]),
                )
                for row in incident_rows
            ],
            paths=[
                self._build_model(
                    PathSummary,
                    target_key=row[0],
                    target_id=row[1],
                    target_kind=row[2],
                    fqdn=row[3],
                    path_hash=row[4],
                    path_preview=row[5] or "",
                    last_seen_utc=self._normalize_timestamp(row[6]),
                    hop_count=int(row[7] or 0),
                    average_hop_latency_ms=row[8],
                )
                for row in path_rows
            ],
        )

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

        return self._build_model(
            ImportSourceStatus,
            source_type=str(row[0]),
            last_run_utc=self._normalize_optional_timestamp(row[1]),
            last_success_utc=self._normalize_optional_timestamp(row[2]),
            last_error=str(row[3]) if row[3] is not None else None,
            last_imported_batch_utc=self._normalize_optional_timestamp(row[4]),
            last_source_identifier=str(row[5]) if row[5] is not None else None,
            last_run_discovered=self._coerce_int(row[6]),
            last_run_imported=self._coerce_int(row[7]),
            last_run_skipped=self._coerce_int(row[8]),
            last_run_failed=self._coerce_int(row[9]),
            last_run_backlog=self._coerce_int(row[10]),
            cumulative_discovered=self._coerce_int(row[11]),
            cumulative_imported=self._coerce_int(row[12]),
            cumulative_skipped=self._coerce_int(row[13]),
            cumulative_failed=self._coerce_int(row[14]),
        )

    @staticmethod
    def _normalize_timestamp(value: datetime | None) -> datetime:
        """DuckDB may return naive UTC timestamps; normalize for API output."""

        if value is None:
            raise ValueError("Incident timestamp must not be null.")
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    @staticmethod
    def _normalize_optional_timestamp(value: object) -> datetime | None:
        """Normalize optional timestamps returned by DuckDB."""

        if value is None:
            return None
        if not isinstance(value, datetime):
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)

    @staticmethod
    def _normalize_metadata(value: object) -> dict[str, object]:
        """Normalize JSON metadata returned by DuckDB."""

        if value is None:
            return {}
        if isinstance(value, dict):
            if "metadata" in value and isinstance(value["metadata"], dict):
                return value["metadata"]
            return value
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError:
                return {}
            if not isinstance(parsed, dict):
                return {}
            if "metadata" in parsed and isinstance(parsed["metadata"], dict):
                return parsed["metadata"]
            return parsed
        return {}

    @staticmethod
    def _coerce_int(value: object) -> int:
        """Normalize nullable numeric aggregates into plain integers."""

        if value is None:
            return 0
        if isinstance(value, bool):
            return int(value)
        if isinstance(value, int):
            return value
        if isinstance(value, float):
            return int(value)
        if isinstance(value, str):
            return int(value)
        return int(cast(Any, value))

    @staticmethod
    def _build_model(model_type: type[TModel], /, **values: object) -> TModel:
        """Instantiate aliased Pydantic models using snake_case field names."""

        return model_type.model_validate(values)
