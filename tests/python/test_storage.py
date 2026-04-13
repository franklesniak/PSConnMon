"""Storage tests for the PSConnMon reporting service."""

from __future__ import annotations

from pathlib import Path

from psconnmon_service.models import EventRecord
from psconnmon_service.storage import StorageRepository


def test_storage_ingests_and_summarizes_events(tmp_path: Path) -> None:
    """Repository operations should preserve summary and target state."""

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    event = EventRecord.model_validate(
        {
            "timestampUtc": "2026-04-09T12:00:00Z",
            "agentId": "branch-01",
            "siteId": "site-a",
            "targetId": "fs01",
            "fqdn": "fs01.corp.local",
            "targetAddress": "10.10.20.15",
            "testType": "ping",
            "probeName": "Ping.Primary",
            "result": "SUCCESS",
            "latencyMs": 12.5,
            "loss": 0.0,
            "errorCode": None,
            "details": "Reply from 10.10.20.15",
            "dnsServer": None,
            "hopIndex": None,
            "hopAddress": None,
            "hopName": None,
            "hopLatencyMs": None,
            "pathHash": None,
            "metadata": {},
        }
    )

    inserted = repository.ingest_events([event])
    summary = repository.get_fleet_summary()
    targets = repository.list_targets()
    agents = repository.list_agents()

    assert inserted == 1
    assert summary.total_events == 1
    assert summary.total_agents == 1
    assert summary.total_targets == 1
    assert targets[0].fqdn == "fs01.corp.local"
    assert targets[0].agent_id == "branch-01"
    assert agents[0].agent_id == "branch-01"


def test_storage_tracks_import_source_status(tmp_path: Path) -> None:
    """Import source status should persist backlog and cumulative counters."""

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    repository.record_import_source_status(
        source_type="local",
        discovered=3,
        imported=2,
        skipped=1,
        failed=0,
        backlog=0,
        last_error=None,
        last_source_identifier=str(tmp_path / "import" / "cycle-001.jsonl"),
        mark_success=True,
        last_imported_batch_utc=None,
    )

    status = repository.get_import_status("local")

    assert status.mode == "local"
    assert status.imported == 2
    assert status.sources[0].source_type == "local"
    assert status.sources[0].cumulative_skipped == 1


def test_storage_ignores_info_events_for_latest_health_state(tmp_path: Path) -> None:
    """Hop-level INFO events should not replace the target health state."""

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    events = [
        EventRecord.model_validate(
            {
                "timestampUtc": "2026-04-09T12:00:00Z",
                "agentId": "branch-01",
                "siteId": "site-a",
                "targetId": "edge-01",
                "fqdn": "edge-01.corp.local",
                "targetAddress": "10.10.20.15",
                "testType": "ping",
                "probeName": "Ping.Primary",
                "result": "SUCCESS",
                "latencyMs": 12.5,
                "loss": 0.0,
                "errorCode": None,
                "details": "Reply from 10.10.20.15",
                "dnsServer": None,
                "hopIndex": None,
                "hopAddress": None,
                "hopName": None,
                "hopLatencyMs": None,
                "pathHash": None,
                "metadata": {},
            }
        ),
        EventRecord.model_validate(
            {
                "timestampUtc": "2026-04-09T12:01:00Z",
                "agentId": "branch-01",
                "siteId": "site-a",
                "targetId": "edge-01",
                "fqdn": "edge-01.corp.local",
                "targetAddress": "8.8.8.8",
                "testType": "traceroute",
                "probeName": "Traceroute.Path",
                "result": "INFO",
                "latencyMs": None,
                "loss": None,
                "errorCode": None,
                "details": "1     1 ms     1 ms     1 ms  10.0.100.1",
                "dnsServer": None,
                "hopIndex": 1,
                "hopAddress": "10.0.100.1",
                "hopName": None,
                "hopLatencyMs": 1.0,
                "pathHash": "abc123",
                "metadata": {"role": "hop"},
            }
        ),
    ]

    repository.ingest_events(events)
    targets = repository.list_targets()
    agents = repository.list_agents()
    sites = repository.list_sites()

    assert targets[0].latest_result == "SUCCESS"
    assert targets[0].last_test_type == "ping"
    assert agents[0].healthy_targets == 1
    assert agents[0].failing_targets == 0
    assert agents[0].timeout_targets == 0
    assert sites[0].failing_targets == 0
