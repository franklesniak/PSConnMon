# Validation Runbook

- **Status:** Active
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-09
- **Scope:** Defines the recommended validation and demonstration flow for
  PSConnMon. Does not define incident-response policy.
- **Related:** [Requirements](../spec/requirements.md), [Architecture](../spec/architecture.md), [README](../../README.md)

## Goal

Demonstrate that PSConnMon can run as a lightweight monitoring service plus a
containerized reporting surface with PingPlotter-style path awareness.

## Demo Assets

- [`samples/config/local-lab.psconnmon.yaml`](../../samples/config/local-lab.psconnmon.yaml)
- [`samples/config/azure-branch.psconnmon.yaml`](../../samples/config/azure-branch.psconnmon.yaml)
- [`samples/ingest/sample-batch.json`](../../samples/ingest/sample-batch.json)

## Local Demo Flow

1. Export or copy a sample config to the operator workspace.
2. Run the PowerShell monitor once with `-RunOnce` to validate the local probe path.
3. Start the reporting service with `docker compose up --build` or `python -m psconnmon_service`.
4. Drop one or more `.jsonl` batches under the configured local import path or
   trigger `POST /api/v1/import/run`.
5. Open the dashboard and walk through summary, target detail, path history,
   incident views, and import freshness.

## Walkthrough

1. Show the YAML or JSON config and explain the multi-target model.
2. Show a live or seeded local-directory import, then optionally show the manual
   HTTP ingest path for testing.
3. Highlight route and latency changes using the built-in dashboard.
4. Explain the Azure-first control plane: managed identity, storage-backed config, and raw batch retention.
5. Close on deployability: local, containerized, and public-cloud friendly without a heavy dependency stack.

## Validation Safeguards

- Keep a known-good local config checked into `samples/config`.
- Keep a seeded ingest batch and one sample `.jsonl` file available for offline demos.
- Do not rely on public internet behavior for the primary path-change story.
- Keep Azure-specific segments optional when the environment network is constrained.
