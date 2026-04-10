"""Contract tests for PSConnMon event models."""

from __future__ import annotations

import pytest

from psconnmon_service.models import EventRecord


def build_event_payload() -> dict[str, object]:
    """Create a valid event payload."""

    return {
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


def test_event_record_accepts_valid_payload() -> None:
    """A valid event payload should be accepted."""

    event = EventRecord.model_validate(build_event_payload())
    assert event.result == "SUCCESS"
    assert event.agent_id == "branch-01"


def test_event_record_rejects_invalid_result() -> None:
    """Unexpected result values should be rejected."""

    payload = build_event_payload()
    payload["result"] = "BROKEN"

    with pytest.raises(ValueError, match="Unsupported result"):
        EventRecord.model_validate(payload)

