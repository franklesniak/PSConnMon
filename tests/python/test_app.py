"""API tests for the PSConnMon reporting service."""

from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from psconnmon_service.app import create_app
from psconnmon_service.config import ServiceSettings


def _write_jsonl_batch(batch_path: Path) -> None:
    """Write one valid JSONL event batch for import tests."""

    batch_path.parent.mkdir(parents=True, exist_ok=True)
    batch_path.write_text(
        "\n".join(
            [
                '{"timestampUtc":"2026-04-09T12:00:00Z","agentId":"branch-01","siteId":"site-a",'
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
        assert status_response.json()["imported"] == 1
        assert status_response.json()["sources"][0]["source_type"] == "local"

        dashboard_response = client.get("/")
        assert dashboard_response.status_code == 200
        assert "Import Health" in dashboard_response.text

        targets_response = client.get("/api/v1/targets")
        assert targets_response.status_code == 200
        assert targets_response.json()[0]["fqdn"] == "fs01.corp.local"


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
    payload = {
        "events": [
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
        ]
    }

    with TestClient(app) as client:
        ingest_response = client.post("/api/v1/ingest/batches", json=payload)
        assert ingest_response.status_code == 200
        assert ingest_response.json()["inserted"] == 1

        summary_response = client.get("/api/v1/summary")
        assert summary_response.status_code == 200
        assert summary_response.json()["total_events"] == 1
