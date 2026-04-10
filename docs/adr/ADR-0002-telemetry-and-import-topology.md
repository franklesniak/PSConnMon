# ADR-0002 Telemetry and Import Topology

- **Status:** Accepted
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-09
- **Scope:** Records the v1 telemetry transport, import topology, and dashboard
  data-store decision. Does not prescribe future analytics integrations.
- **Related:** [Architecture](../spec/architecture.md), [Requirements](../spec/requirements.md), [Roadmap](../../PSConnMon_Roadmap.md)
- **Date:** 2026-04-09

## Context

PSConnMon needs a central reporting path that does not require each monitor to
reach the dashboard directly. The product also needs a lightweight query store
that can run locally and in a simple container.

## Decision

PSConnMon v1 uses this topology:

- Monitors write canonical JSONL batches locally.
- Monitors can upload those batches to Azure Blob Storage.
- The reporting service pulls batches from a local directory, Azure Blob
  Storage, or both.
- DuckDB is the dashboard query store.
- Direct HTTP ingest remains available for manual seeding and tests, but it is
  not the primary deployed telemetry path.

## Consequences

- Positive: Deployed monitors do not need line-of-sight to the dashboard.
- Positive: Azure Blob Storage serves as a simple raw telemetry transport and
  archive.
- Positive: DuckDB keeps the service lightweight and easy to deploy.
- Negative: Import freshness and idempotency must be tracked explicitly.
- Negative: Azure-native analytics backends are deferred rather than built in.

## Alternatives Considered

- Require each agent to post directly to the dashboard.
  Rejected because network reachability and firewall posture are too brittle.
- Use Azure Log Analytics or a dedicated time-series database as the primary
  store.
  Rejected for v1 because the deployment weight and cost model are higher than
  necessary.
- Query Azure Blob Storage directly from the dashboard.
  Rejected because the UI should read from DuckDB only.
