"""Dashboard rendering tests for PSConnMon."""

from __future__ import annotations

from datetime import datetime, timezone

from psconnmon_service.models import FleetSummary, ImportStatus, PathSummary, TargetSummary
from psconnmon_service.ui import render_dashboard


def test_dashboard_renders_string_latency_values() -> None:
    """Dashboard rendering should tolerate string-like numeric values."""

    html = render_dashboard(
        summary=FleetSummary(
            total_events=1,
            total_targets=1,
            active_sites=1,
            failure_events=0,
            timeout_events=0,
            latest_timestamp_utc=datetime.now(timezone.utc),
        ),
        targets=[
            TargetSummary(
                target_id="target-01",
                fqdn="target.local",
                site_id="site-a",
                latest_result="SUCCESS",
                last_latency_ms="12.5",  # type: ignore[arg-type]
                last_timestamp_utc=datetime.now(timezone.utc),
            )
        ],
        paths=[
            PathSummary(
                target_id="target-01",
                fqdn="target.local",
                path_hash="abcd1234",
                last_seen_utc=datetime.now(timezone.utc),
                hop_count=3,
                average_hop_latency_ms="8.1",  # type: ignore[arg-type]
            )
        ],
        incidents=[],
        import_status=ImportStatus(
            mode="local",
            last_run_utc=datetime.now(timezone.utc),
            last_success_utc=datetime.now(timezone.utc),
            last_error=None,
            discovered=1,
            imported=1,
            skipped=0,
            failed=0,
            sources=[],
        ),
    )

    assert "12.50" in html
    assert "8.10" in html
