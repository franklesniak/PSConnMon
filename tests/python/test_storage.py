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
    assert targets[0].target_key == "branch-01::fs01"
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


def test_storage_separates_internet_targets_and_exposes_drilldown_data(tmp_path: Path) -> None:
    """Internet targets should retain their category and drilldown summaries."""

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    events = [
        EventRecord.model_validate(
            {
                "timestampUtc": "2026-04-09T12:00:00Z",
                "agentId": "branch-01",
                "siteId": "site-a",
                "targetId": "internet-cloudflare",
                "fqdn": "Cloudflare DNS",
                "targetAddress": "1.1.1.1",
                "testType": "internetQuality",
                "probeName": "InternetQuality.SampleSet",
                "result": "SUCCESS",
                "latencyMs": 19.5,
                "loss": 0.0,
                "errorCode": None,
                "details": "Average latency 19.50 ms across 5/5 successful samples.",
                "dnsServer": None,
                "hopIndex": None,
                "hopAddress": None,
                "hopName": None,
                "hopLatencyMs": None,
                "pathHash": None,
                "metadata": {"targetKind": "external", "targetClass": "internet"},
            }
        ),
        EventRecord.model_validate(
            {
                "timestampUtc": "2026-04-09T12:01:00Z",
                "agentId": "branch-01",
                "siteId": "site-a",
                "targetId": "internet-cloudflare",
                "fqdn": "Cloudflare DNS",
                "targetAddress": "1.1.1.1",
                "testType": "traceroute",
                "probeName": "Traceroute.Path",
                "result": "INFO",
                "latencyMs": None,
                "loss": None,
                "errorCode": None,
                "details": "1  10.0.100.1  1.000 ms  0.900 ms  0.850 ms",
                "dnsServer": None,
                "hopIndex": 1,
                "hopAddress": "10.0.100.1",
                "hopName": None,
                "hopLatencyMs": 1.0,
                "pathHash": "route-a",
                "metadata": {"targetKind": "external", "targetClass": "internet", "role": "hop"},
            }
        ),
        EventRecord.model_validate(
            {
                "timestampUtc": "2026-04-09T12:01:01Z",
                "agentId": "branch-01",
                "siteId": "site-a",
                "targetId": "internet-cloudflare",
                "fqdn": "Cloudflare DNS",
                "targetAddress": "1.1.1.1",
                "testType": "traceroute",
                "probeName": "Traceroute.Summary",
                "result": "SUCCESS",
                "latencyMs": None,
                "loss": None,
                "errorCode": None,
                "details": "Traceroute completed with 1 hops.",
                "dnsServer": None,
                "hopIndex": None,
                "hopAddress": None,
                "hopName": None,
                "hopLatencyMs": None,
                "pathHash": "route-a",
                "metadata": {
                    "targetKind": "external",
                    "targetClass": "internet",
                    "role": "summary",
                    "hopCount": 1,
                },
            }
        ),
    ]

    repository.ingest_events(events)
    targets = repository.list_targets()
    detail = repository.get_target_detail("branch-01::internet-cloudflare")
    paths = repository.list_paths()

    assert targets[0].target_kind == "external"
    assert targets[0].target_key == "branch-01::internet-cloudflare"
    assert detail is not None
    assert detail.target.target_kind == "external"
    assert {test.test_type for test in detail.tests} == {"internetQuality", "traceroute"}
    assert detail.recent_events[0].metadata["targetClass"] == "internet"
    assert paths[0].path_preview == "10.0.100.1"


def test_storage_keeps_same_target_id_separate_per_agent(tmp_path: Path) -> None:
    """Targets with the same ID on different agents should not collapse together."""

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    events = [
        EventRecord.model_validate(
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
        ),
        EventRecord.model_validate(
            {
                "timestampUtc": "2026-04-09T12:01:00Z",
                "agentId": "branch-02",
                "siteId": "site-a",
                "targetId": "fs01",
                "fqdn": "fs01.corp.local",
                "targetAddress": "10.10.20.15",
                "testType": "share",
                "probeName": "Share.Access",
                "result": "SUCCESS",
                "latencyMs": None,
                "loss": None,
                "errorCode": None,
                "details": "Share access confirmed.",
                "dnsServer": None,
                "hopIndex": None,
                "hopAddress": None,
                "hopName": None,
                "hopLatencyMs": None,
                "pathHash": None,
                "metadata": {},
            }
        ),
    ]

    repository.ingest_events(events)

    summary = repository.get_fleet_summary()
    targets = repository.list_targets()

    assert summary.total_targets == 2
    assert {target.target_key for target in targets} == {"branch-01::fs01", "branch-02::fs01"}
