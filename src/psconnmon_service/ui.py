"""HTML rendering helpers for the PSConnMon dashboard."""

from __future__ import annotations

import json

from .models import DashboardSnapshot

DASHBOARD_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>PSConnMon</title>
    <style>
        :root {
            --bg: #f3efe7;
            --surface: rgba(252, 249, 243, 0.9);
            --surface-strong: rgba(255, 252, 247, 0.96);
            --surface-dark: #1d2527;
            --ink: #1a2223;
            --muted: #5e696b;
            --line: rgba(26, 34, 35, 0.12);
            --accent: #c46f2b;
            --accent-soft: rgba(196, 111, 43, 0.12);
            --ok: #2f7d57;
            --warn: #bf8a2b;
            --bad: #b44336;
            --timeout: #8a5cf5;
            --panel-shadow: 0 22px 60px rgba(24, 34, 36, 0.08);
            --mono: "SFMono-Regular", "IBM Plex Mono", "Cascadia Code", monospace;
            --sans: "Avenir Next", "Segoe UI", sans-serif;
            --serif: "Iowan Old Style", "Palatino Linotype", serif;
        }

        * {
            box-sizing: border-box;
        }

        html {
            scroll-behavior: smooth;
        }

        body {
            margin: 0;
            min-height: 100vh;
            font-family: var(--sans);
            color: var(--ink);
            background:
                radial-gradient(circle at 12% 10%, rgba(196, 111, 43, 0.18), transparent 28%),
                radial-gradient(circle at 88% 12%, rgba(47, 125, 87, 0.18), transparent 24%),
                linear-gradient(180deg, #fbf7f1 0%, var(--bg) 100%);
        }

        body::before {
            content: "";
            position: fixed;
            inset: 0;
            pointer-events: none;
            background-image:
                linear-gradient(rgba(26, 34, 35, 0.02) 1px, transparent 1px),
                linear-gradient(90deg, rgba(26, 34, 35, 0.02) 1px, transparent 1px);
            background-size: 24px 24px;
            mask-image: linear-gradient(180deg, rgba(0, 0, 0, 0.25), transparent 72%);
        }

        button,
        input,
        select {
            font: inherit;
        }

        .shell {
            max-width: 1520px;
            margin: 0 auto;
            padding: 28px 20px 48px;
        }

        .masthead {
            display: grid;
            grid-template-columns: 1.5fr 1fr;
            gap: 20px;
            margin-bottom: 20px;
        }

        .hero,
        .panel {
            background: var(--surface);
            border: 1px solid rgba(255, 255, 255, 0.75);
            border-radius: 26px;
            box-shadow: var(--panel-shadow);
            backdrop-filter: blur(16px);
        }

        .hero {
            padding: 28px;
            position: relative;
            overflow: hidden;
        }

        .hero::after {
            content: "";
            position: absolute;
            inset: auto -8% -30% auto;
            width: 320px;
            height: 320px;
            border-radius: 50%;
            background: radial-gradient(circle, rgba(196, 111, 43, 0.16), transparent 64%);
        }

        .eyebrow {
            margin: 0 0 14px;
            letter-spacing: 0.22em;
            text-transform: uppercase;
            font-size: 0.76rem;
            color: var(--accent);
        }

        h1,
        h2,
        h3 {
            font-family: var(--serif);
            margin: 0;
        }

        h1 {
            font-size: clamp(2.6rem, 6vw, 4.7rem);
            line-height: 0.94;
            max-width: 12ch;
            margin-bottom: 14px;
        }

        .hero-copy {
            max-width: 60ch;
            line-height: 1.65;
            color: var(--muted);
            margin: 0 0 18px;
        }

        .hero-band {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            align-items: center;
        }

        .live-pill,
        .site-chip,
        .status-chip {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 9px 14px;
            border-radius: 999px;
            background: rgba(255, 255, 255, 0.72);
            border: 1px solid rgba(26, 34, 35, 0.1);
            color: var(--ink);
        }

        .live-pill strong,
        .site-chip strong,
        .status-chip strong {
            font-family: var(--mono);
            font-size: 0.92rem;
        }

        .pulse {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: var(--ok);
            box-shadow: 0 0 0 rgba(47, 125, 87, 0.35);
            animation: pulse 1.8s infinite;
        }

        @keyframes pulse {
            0% { box-shadow: 0 0 0 0 rgba(47, 125, 87, 0.35); }
            70% { box-shadow: 0 0 0 14px rgba(47, 125, 87, 0); }
            100% { box-shadow: 0 0 0 0 rgba(47, 125, 87, 0); }
        }

        .hero-aside {
            padding: 20px;
            display: grid;
            gap: 12px;
        }

        .metric-grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 12px;
        }

        .metric-card {
            padding: 18px;
            border-radius: 20px;
            background: var(--surface-strong);
            border: 1px solid rgba(26, 34, 35, 0.08);
            min-height: 120px;
        }

        .metric-card span {
            display: block;
            color: var(--muted);
            font-size: 0.82rem;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 0.12em;
        }

        .metric-card strong {
            display: block;
            font-family: var(--serif);
            font-size: clamp(1.9rem, 3.5vw, 3rem);
            line-height: 1;
        }

        .metric-card small {
            display: block;
            margin-top: 10px;
            color: var(--muted);
        }

        .layout {
            display: grid;
            grid-template-columns: minmax(0, 1.7fr) minmax(340px, 0.9fr);
            gap: 20px;
        }

        .stack {
            display: grid;
            gap: 20px;
        }

        .panel {
            padding: 22px;
        }

        .panel-head {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            gap: 12px;
            margin-bottom: 16px;
        }

        .panel-head p {
            margin: 6px 0 0;
            color: var(--muted);
            line-height: 1.5;
        }

        .agent-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
            gap: 14px;
        }

        .agent-card {
            padding: 18px;
            border-radius: 22px;
            background: linear-gradient(180deg, rgba(255, 255, 255, 0.78), rgba(245, 239, 230, 0.92));
            border: 1px solid rgba(26, 34, 35, 0.1);
            cursor: pointer;
            transition: transform 160ms ease, box-shadow 160ms ease, border-color 160ms ease;
        }

        .agent-card:hover,
        .agent-card.is-active {
            transform: translateY(-2px);
            box-shadow: 0 16px 30px rgba(26, 34, 35, 0.1);
            border-color: rgba(196, 111, 43, 0.4);
        }

        .agent-head,
        .detail-kicker,
        .mini-meta {
            display: flex;
            justify-content: space-between;
            gap: 12px;
            align-items: center;
        }

        .agent-head h3,
        .detail-kicker h3 {
            font-size: 1.2rem;
        }

        .mono {
            font-family: var(--mono);
        }

        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            flex: 0 0 auto;
        }

        .status-success { background: var(--ok); }
        .status-failure { background: var(--bad); }
        .status-timeout { background: var(--timeout); }
        .status-empty, .status-skipped { background: var(--warn); }
        .status-info { background: var(--accent); }
        .status-unknown { background: var(--muted); }

        .agent-gridbar {
            display: grid;
            grid-template-columns: var(--healthy, 1fr) var(--failing, 0fr) var(--timeout, 0fr);
            height: 10px;
            gap: 4px;
            margin: 14px 0 12px;
        }

        .agent-gridbar span {
            display: block;
            border-radius: 999px;
        }

        .agent-gridbar .ok { background: rgba(47, 125, 87, 0.88); }
        .agent-gridbar .bad { background: rgba(180, 67, 54, 0.88); }
        .agent-gridbar .timeout { background: rgba(138, 92, 245, 0.78); }

        .mini-metrics {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 10px;
            margin-top: 12px;
        }

        .mini-metrics article {
            padding: 10px 12px;
            border-radius: 16px;
            background: rgba(255, 255, 255, 0.75);
            border: 1px solid rgba(26, 34, 35, 0.08);
        }

        .mini-metrics span {
            display: block;
            font-size: 0.72rem;
            text-transform: uppercase;
            letter-spacing: 0.12em;
            color: var(--muted);
            margin-bottom: 6px;
        }

        .mini-metrics strong {
            font-size: 1.1rem;
        }

        .site-rail {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }

        .site-chip {
            cursor: pointer;
        }

        .site-chip.is-active {
            background: rgba(196, 111, 43, 0.12);
            border-color: rgba(196, 111, 43, 0.34);
        }

        .command-bar {
            display: grid;
            grid-template-columns: 1.2fr repeat(3, minmax(0, 0.5fr));
            gap: 12px;
            margin-bottom: 16px;
        }

        .field {
            display: grid;
            gap: 8px;
        }

        .field label {
            font-size: 0.76rem;
            text-transform: uppercase;
            letter-spacing: 0.14em;
            color: var(--muted);
        }

        .field input,
        .field select {
            width: 100%;
            border: 1px solid rgba(26, 34, 35, 0.12);
            border-radius: 16px;
            background: rgba(255, 255, 255, 0.82);
            padding: 12px 14px;
            color: var(--ink);
        }

        .status-rail {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 14px;
        }

        .status-chip {
            cursor: pointer;
        }

        .status-chip.is-active {
            background: rgba(26, 34, 35, 0.88);
            color: white;
        }

        .target-table {
            width: 100%;
            border-collapse: collapse;
        }

        .target-table thead th {
            font-size: 0.76rem;
            text-transform: uppercase;
            letter-spacing: 0.14em;
            color: var(--muted);
            padding: 0 0 12px;
        }

        .target-table tbody tr {
            cursor: pointer;
            transition: background 160ms ease, transform 160ms ease;
        }

        .target-table tbody tr:hover,
        .target-table tbody tr.is-active {
            background: rgba(196, 111, 43, 0.08);
        }

        .target-table td {
            padding: 14px 10px 14px 0;
            border-top: 1px solid var(--line);
            vertical-align: top;
        }

        .target-meta {
            color: var(--muted);
            font-size: 0.88rem;
            margin-top: 5px;
        }

        .badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 7px 11px;
            border-radius: 999px;
            font-size: 0.84rem;
            border: 1px solid rgba(26, 34, 35, 0.08);
            background: rgba(255, 255, 255, 0.82);
        }

        .detail-panel {
            position: sticky;
            top: 20px;
            background:
                linear-gradient(180deg, rgba(29, 37, 39, 0.97), rgba(38, 47, 50, 0.96));
            color: #f7f2ea;
            border-radius: 28px;
            padding: 22px;
            box-shadow: 0 22px 80px rgba(17, 24, 25, 0.3);
            min-height: 780px;
        }

        .detail-panel h2,
        .detail-panel h3 {
            color: #fff8ef;
        }

        .detail-panel p,
        .detail-panel li,
        .detail-panel small,
        .detail-panel span {
            color: rgba(247, 242, 234, 0.78);
        }

        .detail-panel .badge {
            background: rgba(255, 255, 255, 0.08);
            border-color: rgba(255, 255, 255, 0.12);
            color: #fff8ef;
        }

        .detail-panel .mini-metrics article {
            background: rgba(255, 255, 255, 0.06);
            border-color: rgba(255, 255, 255, 0.12);
        }

        .detail-chart {
            width: 100%;
            height: 220px;
            border-radius: 22px;
            background:
                linear-gradient(180deg, rgba(255, 255, 255, 0.04), rgba(255, 255, 255, 0.01)),
                radial-gradient(circle at top left, rgba(196, 111, 43, 0.14), transparent 34%);
            border: 1px solid rgba(255, 255, 255, 0.08);
            margin: 18px 0;
        }

        .detail-section + .detail-section {
            margin-top: 20px;
        }

        .timeline-list,
        .event-list {
            display: grid;
            gap: 10px;
            margin: 0;
            padding: 0;
            list-style: none;
        }

        .timeline-list li,
        .event-list li {
            padding: 12px 14px;
            border-radius: 18px;
            background: rgba(255, 255, 255, 0.06);
            border: 1px solid rgba(255, 255, 255, 0.08);
        }

        .event-list li strong,
        .timeline-list li strong {
            display: block;
            color: #fff8ef;
            margin-bottom: 6px;
        }

        .import-grid,
        .path-change-list {
            display: grid;
            gap: 12px;
        }

        .import-card,
        .path-change-card {
            padding: 14px 16px;
            border-radius: 18px;
            background: rgba(255, 255, 255, 0.78);
            border: 1px solid rgba(26, 34, 35, 0.08);
        }

        .import-card .mini-meta,
        .path-change-card .mini-meta {
            margin-bottom: 10px;
        }

        .import-card dl,
        .path-change-card dl {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 10px;
            margin: 0;
        }

        .import-card dt,
        .path-change-card dt {
            font-size: 0.72rem;
            text-transform: uppercase;
            letter-spacing: 0.12em;
            color: var(--muted);
        }

        .import-card dd,
        .path-change-card dd {
            margin: 4px 0 0;
            font-family: var(--mono);
            font-size: 0.9rem;
        }

        .empty-state {
            padding: 18px;
            border-radius: 18px;
            background: rgba(255, 255, 255, 0.72);
            border: 1px dashed rgba(26, 34, 35, 0.14);
            color: var(--muted);
        }

        .muted {
            color: var(--muted);
        }

        .toolbar {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            align-items: center;
        }

        .toolbar button {
            border: 1px solid rgba(26, 34, 35, 0.14);
            border-radius: 999px;
            padding: 10px 14px;
            background: rgba(255, 255, 255, 0.82);
            cursor: pointer;
            transition: background 140ms ease, border-color 140ms ease;
        }

        .toolbar button:hover {
            border-color: rgba(196, 111, 43, 0.42);
            background: rgba(196, 111, 43, 0.09);
        }

        .toolbar button.is-paused {
            background: rgba(180, 67, 54, 0.12);
            border-color: rgba(180, 67, 54, 0.28);
        }

        @media (max-width: 1180px) {
            .masthead,
            .layout {
                grid-template-columns: 1fr;
            }

            .detail-panel {
                position: static;
                min-height: auto;
            }
        }

        @media (max-width: 760px) {
            .metric-grid,
            .command-bar,
            .mini-metrics {
                grid-template-columns: 1fr;
            }

            .shell {
                padding: 18px 14px 32px;
            }

            .panel,
            .hero,
            .detail-panel {
                border-radius: 22px;
            }
        }
    </style>
</head>
<body>
    <div class="shell">
        <section class="masthead">
            <article class="hero">
                <p class="eyebrow">PSConnMon Fleet Board</p>
                <h1>See deployed agents, target health, and path drift as it happens.</h1>
                <p class="hero-copy">
                    This board treats reporting agents as first-class inventory, surfaces source freshness, and
                    keeps target drilldowns live with automatic refresh. Use the filters to isolate a site or
                    agent, then pivot into latency and path history for the selected target.
                </p>
                <div class="hero-band">
                    <div class="live-pill"><span class="pulse"></span><strong id="refresh-state">Live</strong></div>
                    <div class="site-chip"><span>Updated</span><strong id="last-refresh-label">--</strong></div>
                    <div class="site-chip"><span>Import mode</span><strong id="import-mode-label">--</strong></div>
                </div>
            </article>
            <aside class="hero hero-aside">
                <div class="metric-grid" id="metric-grid"></div>
                <div class="toolbar">
                    <button id="refresh-now-button" type="button">Refresh now</button>
                    <button id="toggle-refresh-button" type="button">Pause auto-refresh</button>
                </div>
            </aside>
        </section>

        <section class="layout">
            <div class="stack">
                <article class="panel">
                    <div class="panel-head">
                        <div>
                            <h2>Agent Fleet</h2>
                            <p>Agents are rendered as live reporting surfaces, not just metadata on events.</p>
                        </div>
                        <div class="badge"><span>Reporting agents</span><strong id="agent-count-label">0</strong></div>
                    </div>
                    <div class="agent-grid" id="agent-grid"></div>
                </article>

                <article class="panel">
                    <div class="panel-head">
                        <div>
                            <h2>Sites and Filters</h2>
                            <p>Cut the board by site, agent, result, or a target name/address search.</p>
                        </div>
                    </div>
                    <div class="site-rail" id="site-rail"></div>
                    <div class="command-bar">
                        <div class="field">
                            <label for="target-search">Search</label>
                            <input id="target-search" type="search" placeholder="Target name, address, or agent" />
                        </div>
                        <div class="field">
                            <label for="agent-filter">Agent</label>
                            <select id="agent-filter"></select>
                        </div>
                        <div class="field">
                            <label for="site-filter">Site</label>
                            <select id="site-filter"></select>
                        </div>
                        <div class="field">
                            <label for="status-filter">Result</label>
                            <select id="status-filter"></select>
                        </div>
                    </div>
                    <div class="status-rail" id="status-rail"></div>
                </article>

                <article class="panel">
                    <div class="panel-head">
                        <div>
                            <h2>Target Explorer</h2>
                            <p>Click any target to open an interactive latency and path drilldown.</p>
                        </div>
                        <div class="badge"><span>Visible targets</span><strong id="visible-target-count">0</strong></div>
                    </div>
                    <table class="target-table">
                        <thead>
                            <tr>
                                <th>Target</th>
                                <th>Agent / Site</th>
                                <th>Latest</th>
                                <th>Latency</th>
                                <th>Last seen</th>
                            </tr>
                        </thead>
                        <tbody id="target-table-body"></tbody>
                    </table>
                </article>

                <article class="panel">
                    <div class="panel-head">
                        <div>
                            <h2>Path Changes</h2>
                            <p>Traceroute transitions are summarized separately so routing drift stands out fast.</p>
                        </div>
                    </div>
                    <div class="path-change-list" id="path-change-list"></div>
                </article>

                <article class="panel">
                    <div class="panel-head">
                        <div>
                            <h2>Import Health</h2>
                            <p>Source freshness and backlog are tracked independently from target state.</p>
                        </div>
                    </div>
                    <div class="import-grid" id="import-grid"></div>
                </article>
            </div>

            <aside class="detail-panel">
                <div class="detail-kicker">
                    <div>
                        <p class="eyebrow" style="color: rgba(255, 248, 239, 0.7); margin-bottom: 10px;">Selected Target</p>
                        <h2 id="detail-title">Waiting for data</h2>
                    </div>
                    <div id="detail-status-shell"><div class="badge"><span id="detail-status-label">No target selected</span></div></div>
                </div>

                <div class="mini-metrics" id="detail-metrics"></div>

                <svg class="detail-chart" id="detail-chart" viewBox="0 0 720 220" role="img" aria-label="Latency timeline"></svg>

                <section class="detail-section">
                    <div class="panel-head" style="margin-bottom: 12px;">
                        <div>
                            <h3>Recent incidents</h3>
                            <p class="muted">Latest non-success events for the selected target.</p>
                        </div>
                    </div>
                    <ul class="event-list" id="detail-incidents"></ul>
                </section>

                <section class="detail-section">
                    <div class="panel-head" style="margin-bottom: 12px;">
                        <div>
                            <h3>Path history</h3>
                            <p class="muted">Most recent unique traceroute fingerprints for this target.</p>
                        </div>
                    </div>
                    <ul class="timeline-list" id="detail-paths"></ul>
                </section>
            </aside>
        </section>
    </div>
    <script>
        const REFRESH_INTERVAL_MS = 15000;
        const STATUS_ORDER = ["all", "SUCCESS", "FAILURE", "TIMEOUT", "SKIPPED", "EMPTY", "FATAL", "INFO"];
        const dashboardState = {
            snapshot: __INITIAL_DATA__,
            selectedTargetId: null,
            targetDetail: null,
            filters: {
                search: "",
                agent: "all",
                site: "all",
                status: "all",
            },
            autoRefresh: true,
            refreshTimer: null,
            clockTimer: null,
            isLoading: false,
        };

        function escapeHtml(value) {
            return String(value ?? "")
                .replaceAll("&", "&amp;")
                .replaceAll("<", "&lt;")
                .replaceAll(">", "&gt;")
                .replaceAll('"', "&quot;")
                .replaceAll("'", "&#39;");
        }

        function formatTimestamp(value) {
            if (!value) {
                return "No data";
            }

            const date = new Date(value);
            if (Number.isNaN(date.getTime())) {
                return String(value);
            }

            return date.toLocaleString();
        }

        function formatAgo(value) {
            if (!value) {
                return "No data";
            }

            const deltaMs = Date.now() - new Date(value).getTime();
            const seconds = Math.max(0, Math.floor(deltaMs / 1000));
            if (seconds < 60) {
                return `${seconds}s ago`;
            }

            const minutes = Math.floor(seconds / 60);
            if (minutes < 60) {
                return `${minutes}m ago`;
            }

            const hours = Math.floor(minutes / 60);
            if (hours < 24) {
                return `${hours}h ago`;
            }

            const days = Math.floor(hours / 24);
            return `${days}d ago`;
        }

        function formatNumber(value, digits = 1) {
            if (value === null || value === undefined || value === "") {
                return "--";
            }

            const number = Number(value);
            if (Number.isNaN(number)) {
                return String(value);
            }

            return number.toFixed(digits);
        }

        function getStatusClass(result) {
            const normalized = String(result || "").toUpperCase();
            if (normalized === "SUCCESS") {
                return "status-success";
            }
            if (normalized === "FAILURE" || normalized === "FATAL") {
                return "status-failure";
            }
            if (normalized === "TIMEOUT") {
                return "status-timeout";
            }
            if (normalized === "SKIPPED" || normalized === "EMPTY") {
                return "status-skipped";
            }
            if (normalized === "INFO") {
                return "status-info";
            }
            return "status-unknown";
        }

        function buildStatusBadge(result) {
            return `
                <span class="badge">
                    <span class="status-dot ${getStatusClass(result)}"></span>
                    <strong>${escapeHtml(result || "UNKNOWN")}</strong>
                </span>
            `;
        }

        function getFilteredTargets() {
            const searchTerm = dashboardState.filters.search.trim().toLowerCase();

            return dashboardState.snapshot.targets.filter((target) => {
                if (dashboardState.filters.agent !== "all" && target.agent_id !== dashboardState.filters.agent) {
                    return false;
                }

                if (dashboardState.filters.site !== "all" && target.site_id !== dashboardState.filters.site) {
                    return false;
                }

                if (
                    dashboardState.filters.status !== "all" &&
                    String(target.latest_result).toUpperCase() !== dashboardState.filters.status
                ) {
                    return false;
                }

                if (!searchTerm) {
                    return true;
                }

                const haystack = [
                    target.fqdn,
                    target.target_address,
                    target.agent_id,
                    target.site_id,
                    target.target_id,
                ]
                    .join(" ")
                    .toLowerCase();
                return haystack.includes(searchTerm);
            });
        }

        function pickDefaultTarget(targets) {
            if (!targets.length) {
                return null;
            }

            const degraded = targets.find((target) => String(target.latest_result).toUpperCase() !== "SUCCESS");
            return (degraded || targets[0]).target_id;
        }

        function ensureSelectedTarget() {
            const filteredTargets = getFilteredTargets();
            if (filteredTargets.some((target) => target.target_id === dashboardState.selectedTargetId)) {
                return;
            }

            dashboardState.selectedTargetId = pickDefaultTarget(filteredTargets);
        }

        async function fetchJson(url, options = undefined) {
            const response = await fetch(url, {
                cache: "no-store",
                headers: { Accept: "application/json" },
                ...options,
            });

            if (!response.ok) {
                throw new Error(`Request failed: ${response.status}`);
            }

            return response.json();
        }

        async function refreshDashboard({ forceTargetDetail = true } = {}) {
            if (dashboardState.isLoading) {
                return;
            }

            dashboardState.isLoading = true;
            try {
                dashboardState.snapshot = await fetchJson("/api/v1/dashboard");
                ensureSelectedTarget();
                renderDashboard();

                if (forceTargetDetail && dashboardState.selectedTargetId) {
                    await refreshTargetDetail(dashboardState.selectedTargetId);
                }
            } catch (error) {
                console.error(error);
                document.getElementById("refresh-state").textContent = "Refresh failed";
            } finally {
                dashboardState.isLoading = false;
            }
        }

        async function refreshTargetDetail(targetId) {
            if (!targetId) {
                dashboardState.targetDetail = null;
                renderDetail();
                return;
            }

            try {
                dashboardState.targetDetail = await fetchJson(`/api/v1/targets/${encodeURIComponent(targetId)}`);
            } catch (error) {
                console.error(error);
                dashboardState.targetDetail = null;
            }

            renderDetail();
        }

        function renderMetrics() {
            const summary = dashboardState.snapshot.summary;
            const metricGrid = document.getElementById("metric-grid");
            const freshness = formatAgo(summary.latest_timestamp_utc);

            metricGrid.innerHTML = [
                {
                    label: "Agents",
                    value: summary.total_agents,
                    meta: `${summary.active_sites} active sites`,
                },
                {
                    label: "Targets",
                    value: summary.total_targets,
                    meta: `${summary.total_events} events stored`,
                },
                {
                    label: "Failures",
                    value: summary.failure_events,
                    meta: `${summary.timeout_events} timeout events`,
                },
                {
                    label: "Freshness",
                    value: freshness,
                    meta: formatTimestamp(summary.latest_timestamp_utc),
                },
            ]
                .map(
                    (metric) => `
                        <article class="metric-card">
                            <span>${escapeHtml(metric.label)}</span>
                            <strong>${escapeHtml(metric.value)}</strong>
                            <small>${escapeHtml(metric.meta)}</small>
                        </article>
                    `
                )
                .join("");

            document.getElementById("agent-count-label").textContent = String(summary.total_agents);
            document.getElementById("last-refresh-label").textContent = formatAgo(
                dashboardState.snapshot.refreshedUtc
            );
            document.getElementById("import-mode-label").textContent =
                dashboardState.snapshot.importStatus.mode || "disabled";
        }

        function renderAgents() {
            const agentGrid = document.getElementById("agent-grid");
            const agents = dashboardState.snapshot.agents || [];

            if (!agents.length) {
                agentGrid.innerHTML = '<div class="empty-state">No agents have reported yet.</div>';
                return;
            }

            agentGrid.innerHTML = agents
                .map((agent) => {
                    const selected = dashboardState.filters.agent === agent.agent_id;
                    const total = Math.max(agent.total_targets || 1, 1);
                    const healthy = Math.max(agent.healthy_targets || 0, 0.2);
                    const failing = Math.max(agent.failing_targets || 0, 0.2);
                    const timeout = Math.max(agent.timeout_targets || 0, 0.2);

                    return `
                        <article class="agent-card ${selected ? "is-active" : ""}" data-agent-id="${escapeHtml(
                            agent.agent_id
                        )}">
                            <div class="agent-head">
                                <div>
                                    <h3>${escapeHtml(agent.agent_id)}</h3>
                                    <div class="target-meta">${escapeHtml(agent.site_id)} · ${escapeHtml(
                                        formatAgo(agent.last_timestamp_utc)
                                    )}</div>
                                </div>
                                ${buildStatusBadge(agent.failing_targets > 0 ? "FAILURE" : "SUCCESS")}
                            </div>
                            <div
                                class="agent-gridbar"
                                style="--healthy:${healthy}; --failing:${failing}; --timeout:${timeout};"
                            >
                                <span class="ok"></span>
                                <span class="bad"></span>
                                <span class="timeout"></span>
                            </div>
                            <div class="mini-meta mono">
                                <span>${escapeHtml(String(agent.total_targets))} targets</span>
                                <span>${escapeHtml(formatNumber(agent.average_latency_ms))} ms avg</span>
                            </div>
                            <div class="mini-metrics">
                                <article><span>Healthy</span><strong>${escapeHtml(
                                    String(agent.healthy_targets)
                                )}</strong></article>
                                <article><span>Failing</span><strong>${escapeHtml(
                                    String(agent.failing_targets)
                                )}</strong></article>
                                <article><span>Timeout</span><strong>${escapeHtml(
                                    String(agent.timeout_targets)
                                )}</strong></article>
                            </div>
                        </article>
                    `;
                })
                .join("");
        }

        function renderSites() {
            const siteRail = document.getElementById("site-rail");
            const sites = dashboardState.snapshot.sites || [];

            siteRail.innerHTML = [
                `<button class="site-chip ${dashboardState.filters.site === "all" ? "is-active" : ""}" data-site-id="all" type="button">
                    <span>All sites</span><strong>${escapeHtml(String(sites.length))}</strong>
                </button>`,
                ...sites.map(
                    (site) => `
                        <button
                            class="site-chip ${dashboardState.filters.site === site.site_id ? "is-active" : ""}"
                            data-site-id="${escapeHtml(site.site_id)}"
                            type="button"
                        >
                            <span>${escapeHtml(site.site_id)}</span>
                            <strong>${escapeHtml(String(site.target_count))} targets</strong>
                        </button>
                    `
                ),
            ].join("");
        }

        function renderFilters() {
            const agents = dashboardState.snapshot.agents || [];
            const sites = dashboardState.snapshot.sites || [];
            const statusFilter = document.getElementById("status-filter");
            const agentFilter = document.getElementById("agent-filter");
            const siteFilter = document.getElementById("site-filter");
            const searchInput = document.getElementById("target-search");
            const statusRail = document.getElementById("status-rail");

            searchInput.value = dashboardState.filters.search;

            agentFilter.innerHTML = [
                '<option value="all">All agents</option>',
                ...agents.map(
                    (agent) =>
                        `<option value="${escapeHtml(agent.agent_id)}">${escapeHtml(agent.agent_id)}</option>`
                ),
            ].join("");
            agentFilter.value = dashboardState.filters.agent;

            siteFilter.innerHTML = [
                '<option value="all">All sites</option>',
                ...sites.map(
                    (site) => `<option value="${escapeHtml(site.site_id)}">${escapeHtml(site.site_id)}</option>`
                ),
            ].join("");
            siteFilter.value = dashboardState.filters.site;

            statusFilter.innerHTML = STATUS_ORDER.map(
                (status) => `<option value="${escapeHtml(status)}">${escapeHtml(status)}</option>`
            ).join("");
            statusFilter.value = dashboardState.filters.status;

            statusRail.innerHTML = STATUS_ORDER.map((status) => {
                const active = dashboardState.filters.status === status;
                return `
                    <button
                        class="status-chip ${active ? "is-active" : ""}"
                        data-status-id="${escapeHtml(status)}"
                        type="button"
                    >
                        <strong>${escapeHtml(status)}</strong>
                    </button>
                `;
            }).join("");
        }

        function renderTargets() {
            const tableBody = document.getElementById("target-table-body");
            const filteredTargets = getFilteredTargets();
            document.getElementById("visible-target-count").textContent = String(filteredTargets.length);

            if (!filteredTargets.length) {
                tableBody.innerHTML =
                    '<tr><td colspan="5"><div class="empty-state">No targets match the current filters.</div></td></tr>';
                return;
            }

            tableBody.innerHTML = filteredTargets
                .map(
                    (target) => `
                        <tr class="${dashboardState.selectedTargetId === target.target_id ? "is-active" : ""}" data-target-id="${escapeHtml(
                            target.target_id
                        )}">
                            <td>
                                <strong>${escapeHtml(target.fqdn)}</strong>
                                <div class="target-meta mono">${escapeHtml(target.target_address)}</div>
                            </td>
                            <td>
                                <strong>${escapeHtml(target.agent_id)}</strong>
                                <div class="target-meta">${escapeHtml(target.site_id)}</div>
                            </td>
                            <td>
                                ${buildStatusBadge(target.latest_result)}
                                <div class="target-meta">${escapeHtml(target.last_test_type)}</div>
                            </td>
                            <td class="mono">${escapeHtml(formatNumber(target.last_latency_ms))} ms</td>
                            <td>${escapeHtml(formatAgo(target.last_timestamp_utc))}</td>
                        </tr>
                    `
                )
                .join("");
        }

        function renderImportHealth() {
            const importGrid = document.getElementById("import-grid");
            const status = dashboardState.snapshot.importStatus;
            const sources = status.sources || [];

            if (!sources.length) {
                importGrid.innerHTML =
                    '<div class="empty-state">No import runs recorded yet. The HTTP ingest API remains available.</div>';
                return;
            }

            importGrid.innerHTML = sources
                .map(
                    (source) => `
                        <article class="import-card">
                            <div class="mini-meta">
                                <strong>${escapeHtml(source.source_type)}</strong>
                                ${buildStatusBadge(source.last_error ? "FAILURE" : "SUCCESS")}
                            </div>
                            <dl>
                                <div><dt>Last batch</dt><dd>${escapeHtml(
                                    formatAgo(source.last_imported_batch_utc)
                                )}</dd></div>
                                <div><dt>Imported</dt><dd>${escapeHtml(
                                    String(source.last_run_imported)
                                )}</dd></div>
                                <div><dt>Backlog</dt><dd>${escapeHtml(
                                    String(source.last_run_backlog)
                                )}</dd></div>
                                <div><dt>Errors</dt><dd>${escapeHtml(source.last_error || "none")}</dd></div>
                            </dl>
                        </article>
                    `
                )
                .join("");
        }

        function renderPathChanges() {
            const container = document.getElementById("path-change-list");
            const changes = dashboardState.snapshot.path_changes || [];

            if (!changes.length) {
                container.innerHTML =
                    '<div class="empty-state">No traceroute path changes have been captured yet.</div>';
                return;
            }

            container.innerHTML = changes
                .slice(0, 10)
                .map(
                    (change) => `
                        <article class="path-change-card" data-target-id="${escapeHtml(change.target_id)}">
                            <div class="mini-meta">
                                <strong>${escapeHtml(change.fqdn)}</strong>
                                <span class="muted">${escapeHtml(change.agent_id)} · ${escapeHtml(
                                    formatAgo(change.timestamp_utc)
                                )}</span>
                            </div>
                            <dl>
                                <div><dt>Previous</dt><dd>${escapeHtml(change.previous_path_hash)}</dd></div>
                                <div><dt>Current</dt><dd>${escapeHtml(change.path_hash)}</dd></div>
                                <div><dt>Hops</dt><dd>${escapeHtml(String(change.hop_count))}</dd></div>
                                <div><dt>Site</dt><dd>${escapeHtml(change.site_id)}</dd></div>
                            </dl>
                        </article>
                    `
                )
                .join("");
        }

        function renderDetail() {
            const detail = dashboardState.targetDetail;
            const title = document.getElementById("detail-title");
            const statusShell = document.getElementById("detail-status-shell");
            const metrics = document.getElementById("detail-metrics");
            const incidentList = document.getElementById("detail-incidents");
            const pathList = document.getElementById("detail-paths");

            if (!detail) {
                title.textContent = "Waiting for data";
                statusShell.innerHTML = '<div class="badge"><span id="detail-status-label">No target selected</span></div>';
                metrics.innerHTML = '<article><span>Selection</span><strong>None</strong></article>';
                incidentList.innerHTML = '<li>No incidents available.</li>';
                pathList.innerHTML = '<li>No path history available.</li>';
                drawLatencyChart([]);
                return;
            }

            title.textContent = detail.target.fqdn;
            statusShell.innerHTML = buildStatusBadge(detail.target.latest_result);
            metrics.innerHTML = [
                {
                    label: "Agent",
                    value: detail.target.agent_id,
                },
                {
                    label: "Site",
                    value: detail.target.site_id,
                },
                {
                    label: "Address",
                    value: detail.target.target_address,
                },
                {
                    label: "Last seen",
                    value: formatAgo(detail.target.last_timestamp_utc),
                },
                {
                    label: "Last test",
                    value: detail.target.last_test_type,
                },
                {
                    label: "Latency",
                    value: `${formatNumber(detail.target.last_latency_ms)} ms`,
                },
            ]
                .map(
                    (item) => `
                        <article>
                            <span>${escapeHtml(item.label)}</span>
                            <strong>${escapeHtml(item.value)}</strong>
                        </article>
                    `
                )
                .join("");

            incidentList.innerHTML = detail.incidents.length
                ? detail.incidents
                      .slice(0, 8)
                      .map(
                          (incident) => `
                            <li>
                                <strong>${escapeHtml(incident.test_type)} · ${escapeHtml(incident.result)}</strong>
                                <span>${escapeHtml(incident.details || incident.error_code || "No details")}</span>
                                <div class="target-meta">${escapeHtml(formatTimestamp(incident.timestamp_utc))}</div>
                            </li>
                        `
                      )
                      .join("")
                : "<li>No incidents recorded for this target.</li>";

            pathList.innerHTML = detail.paths.length
                ? detail.paths
                      .map(
                          (path) => `
                            <li>
                                <strong>${escapeHtml(path.path_hash)}</strong>
                                <span>${escapeHtml(String(path.hop_count))} hops · ${escapeHtml(
                                    formatNumber(path.average_hop_latency_ms)
                                )} ms avg</span>
                                <div class="target-meta">${escapeHtml(formatTimestamp(path.last_seen_utc))}</div>
                            </li>
                        `
                      )
                      .join("")
                : "<li>No traceroute history recorded for this target.</li>";

            drawLatencyChart(detail.latency_series || []);
        }

        function drawLatencyChart(series) {
            const chart = document.getElementById("detail-chart");
            const width = 720;
            const height = 220;
            const paddingX = 24;
            const paddingY = 18;
            const innerWidth = width - paddingX * 2;
            const innerHeight = height - paddingY * 2;

            chart.innerHTML = "";

            if (!series.length) {
                chart.innerHTML = `
                    <text x="30" y="44" fill="rgba(247, 242, 234, 0.72)" font-size="14">
                        No latency history available for the selected target.
                    </text>
                `;
                return;
            }

            const numericSeries = series.map((point) => Number(point.latency_ms || 0));
            const maxLatency = Math.max(...numericSeries, 1);
            const points = series.map((point, index) => {
                const x = paddingX + (index / Math.max(series.length - 1, 1)) * innerWidth;
                const latency = Number(point.latency_ms || 0);
                const y = height - paddingY - (latency / maxLatency) * innerHeight;
                return { x, y, point };
            });

            for (let index = 0; index < 4; index += 1) {
                const y = paddingY + (innerHeight / 3) * index;
                const label = maxLatency - (maxLatency / 3) * index;
                chart.innerHTML += `
                    <line x1="${paddingX}" y1="${y}" x2="${width - paddingX}" y2="${y}"
                        stroke="rgba(255,255,255,0.08)" stroke-width="1" />
                    <text x="${width - paddingX}" y="${Math.max(y - 6, 14)}"
                        text-anchor="end" fill="rgba(247,242,234,0.5)" font-size="11">
                        ${escapeHtml(formatNumber(label, 0))} ms
                    </text>
                `;
            }

            const linePath = points
                .map((entry, index) => `${index === 0 ? "M" : "L"} ${entry.x.toFixed(1)} ${entry.y.toFixed(1)}`)
                .join(" ");
            const areaPath = `${linePath} L ${points[points.length - 1].x.toFixed(1)} ${(
                height - paddingY
            ).toFixed(1)} L ${points[0].x.toFixed(1)} ${(height - paddingY).toFixed(1)} Z`;

            chart.innerHTML += `
                <path d="${areaPath}" fill="rgba(196, 111, 43, 0.12)"></path>
                <path d="${linePath}" fill="none" stroke="rgba(255, 214, 176, 0.95)"
                    stroke-width="3" stroke-linecap="round" stroke-linejoin="round"></path>
            `;

            chart.innerHTML += points
                .map((entry) => {
                    const statusClass = getStatusClass(entry.point.result).replace("status-", "");
                    const fill = {
                        success: "#4bd08b",
                        failure: "#ff7f6f",
                        timeout: "#b595ff",
                        skipped: "#ffd073",
                        info: "#ffbe73",
                        unknown: "#d5d0ca",
                    }[statusClass] || "#d5d0ca";

                    return `
                        <circle cx="${entry.x.toFixed(1)}" cy="${entry.y.toFixed(1)}" r="4.5" fill="${fill}">
                            <title>${escapeHtml(
                                `${entry.point.test_type} ${entry.point.result} ${formatNumber(
                                    entry.point.latency_ms
                                )} ms ${formatTimestamp(entry.point.timestamp_utc)}`
                            )}</title>
                        </circle>
                    `;
                })
                .join("");
        }

        function renderDashboard() {
            renderMetrics();
            renderAgents();
            renderSites();
            renderFilters();
            renderTargets();
            renderPathChanges();
            renderImportHealth();
            renderRefreshState();
        }

        function renderRefreshState() {
            const button = document.getElementById("toggle-refresh-button");
            const stateLabel = document.getElementById("refresh-state");
            const refreshed = formatAgo(dashboardState.snapshot.refreshedUtc);
            stateLabel.textContent = dashboardState.autoRefresh ? `Live · ${refreshed}` : `Paused · ${refreshed}`;
            button.textContent = dashboardState.autoRefresh ? "Pause auto-refresh" : "Resume auto-refresh";
            button.classList.toggle("is-paused", !dashboardState.autoRefresh);
        }

        function bindEvents() {
            document.getElementById("refresh-now-button").addEventListener("click", async () => {
                await refreshDashboard();
            });

            document.getElementById("toggle-refresh-button").addEventListener("click", () => {
                dashboardState.autoRefresh = !dashboardState.autoRefresh;
                renderRefreshState();
            });

            document.getElementById("target-search").addEventListener("input", async (event) => {
                dashboardState.filters.search = event.target.value;
                ensureSelectedTarget();
                renderTargets();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("agent-filter").addEventListener("change", async (event) => {
                dashboardState.filters.agent = event.target.value;
                ensureSelectedTarget();
                renderDashboard();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("site-filter").addEventListener("change", async (event) => {
                dashboardState.filters.site = event.target.value;
                ensureSelectedTarget();
                renderDashboard();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("status-filter").addEventListener("change", async (event) => {
                dashboardState.filters.status = event.target.value;
                ensureSelectedTarget();
                renderDashboard();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("agent-grid").addEventListener("click", async (event) => {
                const card = event.target.closest("[data-agent-id]");
                if (!card) {
                    return;
                }

                const agentId = card.dataset.agentId;
                dashboardState.filters.agent = dashboardState.filters.agent === agentId ? "all" : agentId;
                ensureSelectedTarget();
                renderDashboard();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("site-rail").addEventListener("click", async (event) => {
                const button = event.target.closest("[data-site-id]");
                if (!button) {
                    return;
                }

                dashboardState.filters.site = button.dataset.siteId || "all";
                ensureSelectedTarget();
                renderDashboard();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("status-rail").addEventListener("click", async (event) => {
                const button = event.target.closest("[data-status-id]");
                if (!button) {
                    return;
                }

                dashboardState.filters.status = button.dataset.statusId || "all";
                ensureSelectedTarget();
                renderDashboard();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("target-table-body").addEventListener("click", async (event) => {
                const row = event.target.closest("[data-target-id]");
                if (!row) {
                    return;
                }

                dashboardState.selectedTargetId = row.dataset.targetId;
                renderTargets();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });

            document.getElementById("path-change-list").addEventListener("click", async (event) => {
                const card = event.target.closest("[data-target-id]");
                if (!card) {
                    return;
                }

                dashboardState.selectedTargetId = card.dataset.targetId;
                renderTargets();
                await refreshTargetDetail(dashboardState.selectedTargetId);
            });
        }

        function startRefreshLoop() {
            dashboardState.refreshTimer = window.setInterval(async () => {
                if (!dashboardState.autoRefresh) {
                    return;
                }
                await refreshDashboard();
            }, REFRESH_INTERVAL_MS);

            dashboardState.clockTimer = window.setInterval(() => {
                renderRefreshState();
            }, 1000);
        }

        async function bootstrap() {
            ensureSelectedTarget();
            renderDashboard();
            bindEvents();
            await refreshTargetDetail(dashboardState.selectedTargetId);
            startRefreshLoop();
        }

        bootstrap();
    </script>
</body>
</html>
"""


def render_dashboard(snapshot: DashboardSnapshot) -> str:
    """Render the built-in PSConnMon dashboard shell."""

    payload = json.dumps(snapshot.model_dump(mode="json", by_alias=True))
    return DASHBOARD_TEMPLATE.replace("__INITIAL_DATA__", payload)
