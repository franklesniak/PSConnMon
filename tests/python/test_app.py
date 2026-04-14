"""API tests for the PSConnMon reporting service."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from fastapi.testclient import TestClient

from psconnmon_service.app import create_app
from psconnmon_service.config import ServiceSettings


def _write_jsonl_batch(batch_path: Path) -> None:
    """Write one valid JSONL event batch for import tests."""

    batch_path.parent.mkdir(parents=True, exist_ok=True)
    timestamp_utc = (
        datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )
    batch_path.write_text(
        "\n".join(
            [
                f'{{"timestampUtc":"{timestamp_utc}","agentId":"branch-01","siteId":"site-a",'
                '"targetId":"fs01","fqdn":"fs01.corp.local","targetAddress":"10.10.20.15",'
                '"testType":"ping","probeName":"Ping.Primary","result":"SUCCESS","latencyMs":12.5,'
                '"loss":0.0,"errorCode":null,"details":"Reply from 10.10.20.15","dnsServer":null,'
                '"hopIndex":null,"hopAddress":null,"hopName":null,"hopLatencyMs":null,'
                '"pathHash":null,"metadata":{}}'
            ]
        ),
        encoding="utf-8",
    )


def test_dashboard_and_import_endpoints(tmp_path: Path) -> None:
    """The dashboard, manual import, and status endpoints should be available."""

    import_root = tmp_path / "import"
    _write_jsonl_batch(import_root / "site-a" / "cycle-001.jsonl")

    settings = ServiceSettings(
        database_path=tmp_path / "psconnmon.duckdb",
        import_mode="local",
        import_interval_seconds=30,
        import_local_path=import_root,
        azure_storage_account="",
        azure_storage_container="",
        azure_blob_prefix="events",
        azure_auth_mode="managedIdentity",
        azure_sas_token="",
        azure_blob_service_url="",
    )

    app = create_app(settings=settings)
    with TestClient(app) as client:
        response = client.get("/healthz")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

        import_response = client.post("/api/v1/import/run")
        assert import_response.status_code == 200
        assert import_response.json()["skipped"] >= 1

        status_response = client.get("/api/v1/import/status")
        assert status_response.status_code == 200
        assert status_response.json()["mode"] == "local"
        assert status_response.json()["cumulative_imported"] == 1
        assert status_response.json()["sources"][0]["source_type"] == "local"

        dashboard_data_response = client.get("/api/v1/dashboard")
        assert dashboard_data_response.status_code == 200
        assert dashboard_data_response.json()["summary"]["total_agents"] == 1
        assert dashboard_data_response.json()["agents"][0]["agent_id"] == "branch-01"

        minute_window_response = client.get("/api/v1/dashboard?summary_window_minutes=30")
        assert minute_window_response.status_code == 200
        assert minute_window_response.json()["summary"]["total_events"] == 1

        # summary_window_minutes=0 should return all history (unbounded window)
        zero_window_response = client.get("/api/v1/summary?summary_window_minutes=0")
        assert zero_window_response.status_code == 200
        assert zero_window_response.json()["total_events"] >= 1

        dashboard_response = client.get("/")
        assert dashboard_response.status_code == 200
        assert "PSConnMon Fleet Board" in dashboard_response.text
        assert "Agent Fleet" in dashboard_response.text
        assert "Internal Targets" in dashboard_response.text
        assert "Internet Targets" in dashboard_response.text

        agents_response = client.get("/api/v1/agents")
        assert agents_response.status_code == 200
        assert agents_response.json()[0]["agent_id"] == "branch-01"

        targets_response = client.get("/api/v1/targets")
        assert targets_response.status_code == 200
        assert targets_response.json()[0]["fqdn"] == "fs01.corp.local"
        assert targets_response.json()[0]["agent_id"] == "branch-01"

        target_detail_response = client.get("/api/v1/targets/branch-01%3A%3Afs01?window_minutes=30")
        assert target_detail_response.status_code == 200
        assert target_detail_response.json()["target"]["fqdn"] == "fs01.corp.local"
        assert len(target_detail_response.json()["recent_events"]) == 1


def test_http_ingest_remains_available(tmp_path: Path) -> None:
    """The direct HTTP ingest path should remain available for manual seeding."""

    settings = ServiceSettings(
        database_path=tmp_path / "psconnmon.duckdb",
        import_mode="disabled",
        import_interval_seconds=30,
        import_local_path=tmp_path / "import",
        azure_storage_account="",
        azure_storage_container="",
        azure_blob_prefix="events",
        azure_auth_mode="managedIdentity",
        azure_sas_token="",
        azure_blob_service_url="",
    )

    app = create_app(settings=settings)
    timestamp_utc = (
        datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )
    payload = {
        "events": [
            {
                "timestampUtc": timestamp_utc,
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
        ]
    }

    with TestClient(app) as client:
        ingest_response = client.post("/api/v1/ingest/batches", json=payload)
        assert ingest_response.status_code == 200
        assert ingest_response.json()["inserted"] == 1

        summary_response = client.get("/api/v1/summary")
        assert summary_response.status_code == 200
        assert summary_response.json()["total_events"] == 1


def test_domain_auth_events_surface_without_special_casing(tmp_path: Path) -> None:
    """Domain auth events should ingest and surface through the target APIs."""

    settings = ServiceSettings(
        database_path=tmp_path / "psconnmon.duckdb",
        import_mode="disabled",
        import_interval_seconds=30,
        import_local_path=tmp_path / "import",
        azure_storage_account="",
        azure_storage_container="",
        azure_blob_prefix="events",
        azure_auth_mode="managedIdentity",
        azure_sas_token="",
        azure_blob_service_url="",
    )

    app = create_app(settings=settings)
    timestamp_utc = (
        datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )
    payload = {
        "events": [
            {
                "timestampUtc": timestamp_utc,
                "agentId": "pi-branch-01",
                "siteId": "site-a",
                "targetId": "dc01",
                "fqdn": "dc01.corp.local",
                "targetAddress": "10.10.0.10",
                "testType": "domainAuth",
                "probeName": "DomainAuth.Kerberos",
                "result": "SUCCESS",
                "latencyMs": None,
                "loss": None,
                "errorCode": None,
                "details": "Kerberos ticket acquisition and validation succeeded.",
                "dnsServer": None,
                "hopIndex": None,
                "hopAddress": None,
                "hopName": None,
                "hopLatencyMs": None,
                "pathHash": None,
                "metadata": {"linuxProfileId": "dc-keytab"},
            }
        ]
    }

    with TestClient(app) as client:
        ingest_response = client.post("/api/v1/ingest/batches", json=payload)
        assert ingest_response.status_code == 200
        assert ingest_response.json()["inserted"] == 1

        targets_response = client.get("/api/v1/targets")
        assert targets_response.status_code == 200
        assert targets_response.json()[0]["last_test_type"] == "domainAuth"

        target_detail_response = client.get("/api/v1/targets/pi-branch-01%3A%3Adc01")
        assert target_detail_response.status_code == 200
        assert target_detail_response.json()["target"]["last_test_type"] == "domainAuth"
