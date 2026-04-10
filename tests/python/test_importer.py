"""Import worker tests for the PSConnMon reporting service."""

from __future__ import annotations

from pathlib import Path

from psconnmon_service.config import ServiceSettings
from psconnmon_service.importer import ImportBatch, ImportManager
from psconnmon_service.storage import StorageRepository


def _make_settings(tmp_path: Path, import_mode: str = "local") -> ServiceSettings:
    """Create test service settings."""

    return ServiceSettings(
        database_path=tmp_path / "psconnmon.duckdb",
        import_mode=import_mode,
        import_interval_seconds=30,
        import_local_path=tmp_path / "import",
        azure_storage_account="account",
        azure_storage_container="telemetry",
        azure_blob_prefix="events",
        azure_auth_mode="managedIdentity",
        azure_sas_token="",
        azure_blob_service_url="",
    )


def _write_jsonl(batch_path: Path, content: str) -> None:
    """Write one test batch file."""

    batch_path.parent.mkdir(parents=True, exist_ok=True)
    batch_path.write_text(content, encoding="utf-8")


def test_import_manager_imports_local_batches_and_skips_duplicates(tmp_path: Path) -> None:
    """Local import runs should ingest once and then skip the same batch fingerprint."""

    event_line = (
        '{"timestampUtc":"2026-04-09T12:00:00Z","agentId":"branch-01","siteId":"site-a",'
        '"targetId":"fs01","fqdn":"fs01.corp.local","targetAddress":"10.10.20.15",'
        '"testType":"ping","probeName":"Ping.Primary","result":"SUCCESS","latencyMs":12.5,'
        '"loss":0.0,"errorCode":null,"details":"Reply from 10.10.20.15","dnsServer":null,'
        '"hopIndex":null,"hopAddress":null,"hopName":null,"hopLatencyMs":null,'
        '"pathHash":null,"metadata":{}}'
    )
    _write_jsonl(tmp_path / "import" / "cycle-001.jsonl", event_line)

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    manager = ImportManager(repository, _make_settings(tmp_path))

    first_status = manager.run_once()
    second_status = manager.run_once()

    assert first_status.imported == 1
    assert second_status.skipped >= 1
    assert repository.get_fleet_summary().total_events == 1


def test_import_manager_records_invalid_jsonl_failures(tmp_path: Path) -> None:
    """Invalid JSONL batches should fail without partial event ingestion."""

    _write_jsonl(tmp_path / "import" / "cycle-001.jsonl", "{not-json}\n")

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    manager = ImportManager(repository, _make_settings(tmp_path))
    status = manager.run_once()

    assert status.failed == 1
    assert repository.get_fleet_summary().total_events == 0
    assert "Invalid JSON" in (status.last_error or "")


def test_import_manager_supports_hybrid_mode_with_fake_azure_source(tmp_path: Path, monkeypatch) -> None:
    """Hybrid mode should ingest local and Azure batches without duplicate conflicts."""

    local_line = (
        '{"timestampUtc":"2026-04-09T12:00:00Z","agentId":"branch-01","siteId":"site-a",'
        '"targetId":"local-01","fqdn":"local-01.corp.local","targetAddress":"10.10.20.15",'
        '"testType":"ping","probeName":"Ping.Primary","result":"SUCCESS","latencyMs":12.5,'
        '"loss":0.0,"errorCode":null,"details":"Reply from 10.10.20.15","dnsServer":null,'
        '"hopIndex":null,"hopAddress":null,"hopName":null,"hopLatencyMs":null,'
        '"pathHash":null,"metadata":{}}'
    )
    _write_jsonl(tmp_path / "import" / "cycle-001.jsonl", local_line)

    class FakeAzureSource:
        source_type = "azure"

        def iter_batches(self) -> list[ImportBatch]:
            return [
                ImportBatch(
                    source_type="azure",
                    source_identifier="events/site-a/cycle-azure-001.jsonl",
                    fingerprint="etag-001",
                    content=(
                        '{"timestampUtc":"2026-04-09T12:00:05Z","agentId":"branch-02","siteId":"site-b",'
                        '"targetId":"azure-01","fqdn":"azure-01.corp.local","targetAddress":"10.10.30.15",'
                        '"testType":"ping","probeName":"Ping.Primary","result":"SUCCESS","latencyMs":15.0,'
                        '"loss":0.0,"errorCode":null,"details":"Reply from 10.10.30.15","dnsServer":null,'
                        '"hopIndex":null,"hopAddress":null,"hopName":null,"hopLatencyMs":null,'
                        '"pathHash":null,"metadata":{}}'
                    ),
                )
            ]

    repository = StorageRepository(tmp_path / "psconnmon.duckdb")
    manager = ImportManager(repository, _make_settings(tmp_path, import_mode="hybrid"))
    local_source = manager._build_sources()[0]
    monkeypatch.setattr(manager, "_build_sources", lambda: [local_source, FakeAzureSource()])

    status = manager.run_once()

    assert status.imported == 2
    assert {source.source_type for source in status.sources} == {"azure", "local"}
    assert repository.get_fleet_summary().total_events == 2
