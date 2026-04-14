"""Dashboard rendering tests for PSConnMon."""

from __future__ import annotations

from datetime import datetime, timezone

from psconnmon_service.models import (
    AgentSummary,
    DashboardSnapshot,
    FleetSummary,
    ImportStatus,
    IncidentSummary,
    PathSummary,
    SiteSummary,
    TargetSummary,
)
from psconnmon_service.ui import render_dashboard


def test_dashboard_renders_live_board_shell() -> None:
    """Dashboard rendering should expose the live board sections and payload."""

    html = render_dashboard(
        DashboardSnapshot(
            summary=FleetSummary(
                total_events=1,
                total_agents=1,
                total_targets=1,
                active_sites=1,
                failure_events=0,
                timeout_events=0,
                latest_timestamp_utc=datetime.now(timezone.utc),
            ),
            agents=[
                AgentSummary(
                    agent_id="agent-01",
                    site_id="site-a",
                    total_targets=1,
                    healthy_targets=1,
                    failing_targets=0,
                    timeout_targets=0,
                    average_latency_ms=12.5,
                    last_timestamp_utc=datetime.now(timezone.utc),
                )
            ],
            sites=[
                SiteSummary(
                    site_id="site-a",
                    agent_count=1,
                    target_count=1,
                    failing_targets=0,
                    average_latency_ms=12.5,
                    last_timestamp_utc=datetime.now(timezone.utc),
                )
            ],
            targets=[
                TargetSummary.model_validate(
                    {
                        "target_key": "agent-01::target-01",
                        "target_id": "target-01",
                        "target_kind": "internal",
                        "agent_id": "agent-01",
                        "fqdn": "target.local",
                        "site_id": "site-a",
                        "target_address": "10.0.0.10",
                        "latest_result": "SUCCESS",
                        "last_test_type": "ping",
                        "last_latency_ms": 12.5,
                        "last_timestamp_utc": datetime.now(timezone.utc),
                    }
                )
            ],
            paths=[
                PathSummary.model_validate(
                    {
                        "target_key": "agent-01::target-01",
                        "target_id": "target-01",
                        "target_kind": "internal",
                        "fqdn": "target.local",
                        "path_hash": "abcd1234",
                        "path_preview": "edge-gateway -> target.local",
                        "last_seen_utc": datetime.now(timezone.utc),
                        "hop_count": 3,
                        "average_hop_latency_ms": 8.1,
                    }
                )
            ],
            path_changes=[],
            incidents=[],
            import_status=ImportStatus(
                mode="local",
                last_run_utc=datetime.now(timezone.utc),
                last_success_utc=datetime.now(timezone.utc),
                last_error=None,
                cumulative_discovered=1,
                cumulative_imported=1,
                cumulative_skipped=0,
                cumulative_failed=0,
                sources=[],
            ),
            refreshed_utc=datetime.now(timezone.utc),
        )
    )

    assert "Agent Fleet" in html
    assert "PSConnMon Fleet Board" in html
    assert "Internal Targets" in html
    assert "Internet Targets" in html
    assert "target.local" in html
    assert '"target_id": "target-01"' in html


def test_dashboard_escapes_script_closing_tags() -> None:
    """Fields containing </script> must not break out of the inline script block."""

    now = datetime.now(timezone.utc)
    html = render_dashboard(
        DashboardSnapshot(
            summary=FleetSummary(
                total_events=1,
                total_agents=1,
                total_targets=1,
                active_sites=1,
                failure_events=1,
                timeout_events=0,
                latest_timestamp_utc=now,
            ),
            agents=[
                AgentSummary(
                    agent_id="agent-01",
                    site_id="site-a",
                    total_targets=1,
                    healthy_targets=0,
                    failing_targets=1,
                    timeout_targets=0,
                    average_latency_ms=None,
                    last_timestamp_utc=now,
                )
            ],
            sites=[
                SiteSummary(
                    site_id="site-a",
                    agent_count=1,
                    target_count=1,
                    failing_targets=1,
                    average_latency_ms=None,
                    last_timestamp_utc=now,
                )
            ],
            targets=[
                TargetSummary.model_validate(
                    {
                        "target_key": "agent-01::target-01",
                        "target_id": "target-01",
                        "target_kind": "internal",
                        "agent_id": "agent-01",
                        "fqdn": "target.local",
                        "site_id": "site-a",
                        "target_address": "10.0.0.10",
                        "latest_result": "FAILURE",
                        "last_test_type": "ping",
                        "last_latency_ms": None,
                        "last_timestamp_utc": now,
                    }
                )
            ],
            paths=[],
            path_changes=[],
            incidents=[
                IncidentSummary(
                    target_key="agent-01::target-01",
                    target_id="target-01",
                    fqdn="target.local",
                    test_type="ping",
                    result="FAILURE",
                    error_code=None,
                    details='evil</script><script>alert("xss")</script>',
                    timestamp_utc=now,
                )
            ],
            import_status=ImportStatus(
                mode="disabled",
                last_run_utc=None,
                last_success_utc=None,
                last_error=None,
                cumulative_discovered=0,
                cumulative_imported=0,
                cumulative_skipped=0,
                cumulative_failed=0,
                sources=[],
            ),
            refreshed_utc=now,
        )
    )

    # The literal </script> must be escaped so it cannot close the inline block.
    assert "</script><script>" not in html
    assert r"<\/script>" in html
