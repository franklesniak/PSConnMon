"""HTML rendering helpers for the PSConnMon dashboard."""

from __future__ import annotations

import html
import json
from datetime import datetime

from .models import FleetSummary, ImportStatus, IncidentSummary, PathSummary, TargetSummary


def _format_timestamp(value: datetime | None) -> str:
    if value is None:
        return "No data"
    return value.isoformat()


def _format_number(value: object | None) -> str:
    """Format numeric values defensively for dashboard rendering."""

    if value is None:
        return ""

    try:
        return f"{float(value):.2f}"
    except (TypeError, ValueError):
        return html.escape(str(value))


def render_dashboard(
    summary: FleetSummary,
    targets: list[TargetSummary],
    paths: list[PathSummary],
    incidents: list[IncidentSummary],
    import_status: ImportStatus,
) -> str:
    """Render the built-in PSConnMon dashboard."""

    target_rows = "\n".join(
        (
            "<tr>"
            f"<td>{html.escape(target.fqdn)}</td>"
            f"<td>{html.escape(target.site_id)}</td>"
            f"<td>{html.escape(target.latest_result)}</td>"
            f"<td>{_format_number(target.last_latency_ms)}</td>"
            f"<td>{html.escape(_format_timestamp(target.last_timestamp_utc))}</td>"
            "</tr>"
        )
        for target in targets
    )

    path_rows = "\n".join(
        (
            "<tr>"
            f"<td>{html.escape(path.fqdn)}</td>"
            f"<td>{html.escape(path.path_hash)}</td>"
            f"<td>{path.hop_count}</td>"
            f"<td>{_format_number(path.average_hop_latency_ms)}</td>"
            f"<td>{html.escape(_format_timestamp(path.last_seen_utc))}</td>"
            "</tr>"
        )
        for path in paths[:10]
    )

    incident_rows = "\n".join(
        (
            "<article class=\"incident\">"
            f"<h3>{html.escape(incident.fqdn)} · {html.escape(incident.test_type)}</h3>"
            f"<p class=\"status\">{html.escape(incident.result)}</p>"
            f"<p>{html.escape(incident.details)}</p>"
            f"<p class=\"meta\">{html.escape(_format_timestamp(incident.timestamp_utc))}</p>"
            "</article>"
        )
        for incident in incidents[:8]
    )

    import_rows = "\n".join(
        (
            "<tr>"
            f"<td>{html.escape(source.source_type)}</td>"
            f"<td>{html.escape(_format_timestamp(source.last_imported_batch_utc))}</td>"
            f"<td>{source.last_run_imported}</td>"
            f"<td>{source.last_run_backlog}</td>"
            f"<td>{html.escape(source.last_error or '')}</td>"
            "</tr>"
        )
        for source in import_status.sources
    )

    chart_data = {
        "targets": [
            {
                "fqdn": target.fqdn,
                "latencyMs": target.last_latency_ms or 0,
                "status": target.latest_result,
            }
            for target in targets[:12]
        ]
    }

    return f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>PSConnMon</title>
    <style>
        :root {{
            --bg: #f4efe6;
            --panel: rgba(255, 251, 245, 0.82);
            --ink: #1c2a2b;
            --muted: #5a6a6b;
            --accent: #c35b3a;
            --grid: rgba(28, 42, 43, 0.12);
            --ok: #2d7a52;
            --warn: #b36f2b;
            --bad: #a63a32;
        }}

        * {{
            box-sizing: border-box;
        }}

        body {{
            margin: 0;
            font-family: "Avenir Next", "Segoe UI", sans-serif;
            color: var(--ink);
            background:
                radial-gradient(circle at top left, rgba(195, 91, 58, 0.18), transparent 35%),
                radial-gradient(circle at bottom right, rgba(45, 122, 82, 0.14), transparent 30%),
                linear-gradient(180deg, #fff8ef 0%, var(--bg) 100%);
        }}

        .shell {{
            max-width: 1320px;
            margin: 0 auto;
            padding: 32px 24px 48px;
        }}

        .hero {{
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 24px;
            align-items: end;
            margin-bottom: 24px;
        }}

        .hero-card,
        .panel {{
            background: var(--panel);
            backdrop-filter: blur(12px);
            border: 1px solid rgba(255, 255, 255, 0.6);
            border-radius: 24px;
            box-shadow: 0 24px 80px rgba(28, 42, 43, 0.08);
        }}

        .hero-card {{
            padding: 28px;
        }}

        h1, h2, h3 {{
            font-family: "Iowan Old Style", "Palatino Linotype", serif;
            margin: 0;
        }}

        h1 {{
            font-size: clamp(2.6rem, 5vw, 4.4rem);
            line-height: 0.94;
            margin-bottom: 12px;
        }}

        .eyebrow {{
            letter-spacing: 0.22em;
            text-transform: uppercase;
            font-size: 0.78rem;
            color: var(--accent);
            margin-bottom: 14px;
        }}

        .hero-copy {{
            max-width: 54ch;
            color: var(--muted);
            font-size: 1.02rem;
            line-height: 1.6;
        }}

        .stats,
        .mini-grid {{
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 12px;
        }}

        .mini-grid {{
            grid-template-columns: repeat(3, minmax(0, 1fr));
            margin-top: 18px;
        }}

        .stat {{
            padding: 18px;
        }}

        .stat strong {{
            display: block;
            font-size: 2rem;
            color: var(--ink);
        }}

        .grid {{
            display: grid;
            grid-template-columns: 1.4fr 1fr;
            gap: 24px;
        }}

        .panel {{
            padding: 22px;
        }}

        .panel + .panel {{
            margin-top: 24px;
        }}

        .chart {{
            width: 100%;
            height: 260px;
        }}

        table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 0.94rem;
        }}

        th, td {{
            padding: 10px 0;
            border-bottom: 1px solid var(--grid);
            text-align: left;
            vertical-align: top;
        }}

        .incident-stack {{
            display: grid;
            gap: 14px;
        }}

        .incident {{
            padding: 16px 18px;
            border-radius: 18px;
            background: rgba(255, 255, 255, 0.68);
            border: 1px solid rgba(195, 91, 58, 0.18);
        }}

        .status {{
            color: var(--bad);
            font-weight: 700;
        }}

        .meta {{
            color: var(--muted);
            font-size: 0.88rem;
        }}

        @media (max-width: 980px) {{
            .hero,
            .grid,
            .mini-grid {{
                grid-template-columns: 1fr;
            }}
        }}
    </style>
</head>
<body>
    <div class="shell">
        <section class="hero">
            <article class="hero-card">
                <p class="eyebrow">PSConnMon Dashboard</p>
                <h1>Path-centric monitoring for hybrid networks.</h1>
                <p class="hero-copy">
                    PSConnMon collects structured probe events from PowerShell agents and turns them into a
                    lightweight PingPlotter-style operational surface. The service keeps hot query data local
                    while remaining simple to deploy on a laptop, a branch server, or Azure Container Apps.
                </p>
                <div class="mini-grid">
                    <article class="hero-card stat">
                        <span>Import mode</span>
                        <strong style="font-size:1rem;">{html.escape(import_status.mode)}</strong>
                    </article>
                    <article class="hero-card stat">
                        <span>Batches imported</span>
                        <strong>{import_status.imported}</strong>
                    </article>
                    <article class="hero-card stat">
                        <span>Import errors</span>
                        <strong>{import_status.failed}</strong>
                    </article>
                </div>
            </article>
            <div class="stats">
                <article class="hero-card stat">
                    <span>Total events</span>
                    <strong>{summary.total_events}</strong>
                </article>
                <article class="hero-card stat">
                    <span>Targets</span>
                    <strong>{summary.total_targets}</strong>
                </article>
                <article class="hero-card stat">
                    <span>Failing probes</span>
                    <strong>{summary.failure_events}</strong>
                </article>
                <article class="hero-card stat">
                    <span>Latest event</span>
                    <strong style="font-size:1rem;">{html.escape(_format_timestamp(summary.latest_timestamp_utc))}</strong>
                </article>
            </div>
        </section>

        <section class="grid">
            <div>
                <article class="panel">
                    <h2>Latency Snapshot</h2>
                    <svg class="chart" viewBox="0 0 700 260" role="img" aria-label="Latency chart"></svg>
                </article>
                <article class="panel">
                    <h2>Fleet Targets</h2>
                    <table>
                        <thead>
                            <tr>
                                <th>Target</th>
                                <th>Site</th>
                                <th>Status</th>
                                <th>Latency (ms)</th>
                                <th>Last Seen</th>
                            </tr>
                        </thead>
                        <tbody>
                            {target_rows or '<tr><td colspan="5">No events ingested yet.</td></tr>'}
                        </tbody>
                    </table>
                </article>
            </div>
            <div>
                <article class="panel">
                    <h2>Import Health</h2>
                    <table>
                        <thead>
                            <tr>
                                <th>Source</th>
                                <th>Last Batch</th>
                                <th>Last Imported</th>
                                <th>Backlog</th>
                                <th>Last Error</th>
                            </tr>
                        </thead>
                        <tbody>
                            {import_rows or '<tr><td colspan="5">No import runs recorded yet.</td></tr>'}
                        </tbody>
                    </table>
                </article>
                <article class="panel">
                    <h2>Path Inventory</h2>
                    <table>
                        <thead>
                            <tr>
                                <th>Target</th>
                                <th>Path</th>
                                <th>Hops</th>
                                <th>Avg Hop Latency</th>
                                <th>Last Seen</th>
                            </tr>
                        </thead>
                        <tbody>
                            {path_rows or '<tr><td colspan="5">No traceroute data yet.</td></tr>'}
                        </tbody>
                    </table>
                </article>
                <article class="panel">
                    <h2>Recent Incidents</h2>
                    <div class="incident-stack">
                        {incident_rows or '<p>No incidents captured.</p>'}
                    </div>
                </article>
            </div>
        </section>
    </div>
    <script>
        const chartData = {json.dumps(chart_data)};
        const svg = document.querySelector(".chart");
        const maxLatency = Math.max(...chartData.targets.map((item) => item.latencyMs), 1);
        const barWidth = 42;
        const gap = 14;

        chartData.targets.forEach((item, index) => {{
            const height = Math.max(10, (item.latencyMs / maxLatency) * 190);
            const x = 36 + index * (barWidth + gap);
            const y = 220 - height;
            const color = item.status === "SUCCESS" ? "#2d7a52" : item.status === "TIMEOUT" ? "#b36f2b" : "#a63a32";

            const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
            rect.setAttribute("x", x);
            rect.setAttribute("y", y);
            rect.setAttribute("width", barWidth);
            rect.setAttribute("height", height);
            rect.setAttribute("rx", 12);
            rect.setAttribute("fill", color);
            rect.style.opacity = "0";
            rect.style.transformOrigin = `${{x + barWidth / 2}}px 220px`;
            rect.style.transform = "scaleY(0.1)";
            rect.style.transition = `opacity 450ms ease ${{index * 70}}ms, transform 450ms ease ${{index * 70}}ms`;
            svg.appendChild(rect);

            const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
            label.setAttribute("x", x + barWidth / 2);
            label.setAttribute("y", 244);
            label.setAttribute("text-anchor", "middle");
            label.setAttribute("font-size", "11");
            label.setAttribute("fill", "#5a6a6b");
            label.textContent = item.fqdn.slice(0, 10);
            svg.appendChild(label);

            const value = document.createElementNS("http://www.w3.org/2000/svg", "text");
            value.setAttribute("x", x + barWidth / 2);
            value.setAttribute("y", y - 8);
            value.setAttribute("text-anchor", "middle");
            value.setAttribute("font-size", "11");
            value.setAttribute("fill", "#1c2a2b");
            value.textContent = `${{item.latencyMs.toFixed(1)}}ms`;
            svg.appendChild(value);

            requestAnimationFrame(() => {{
                rect.style.opacity = "1";
                rect.style.transform = "scaleY(1)";
            }});
        }});
    </script>
</body>
</html>
"""
