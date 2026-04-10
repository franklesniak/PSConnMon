# ADR-0001 Agent and Service Split

- **Status:** Accepted
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-09
- **Scope:** Records the decision to split PSConnMon into a PowerShell monitor
  and Python reporting service. Does not prescribe UI polish or release timing.
- **Related:** [Architecture](../spec/architecture.md), [Requirements](../spec/requirements.md), [Roadmap](../../PSConnMon_Roadmap.md)
- **Date:** 2026-04-09

## Context

The prior single-script model can collect useful connectivity data, but it is
not a good fit for reporting, cloud delivery, or independent
service deployment. The product needs a lightweight operator experience without
forcing Windows-only hosting for the dashboard tier.

## Decision

PSConnMon will use two deployable components:

- A **PowerShell monitor** for network-adjacent probes, local spooling, and Azure
  config polling.
- A **Python reporting service** for ingestion, query, and visualization.

## Consequences

- Positive: The PowerShell side stays close to the network while the dashboard
  stays easy to containerize.
- Positive: The reporting UI can use Python web tooling and DuckDB without
  bloating the monitor.
- Positive: Azure deployment maps cleanly to Container Apps plus Storage.
- Negative: The repo now has dual-language build and test responsibilities.
- Negative: Shared contracts must be maintained carefully between PowerShell and
  Python.

## Alternatives Considered

- Keep a single PowerShell-only application.
  Rejected because the built-in dashboard and container delivery would be
  weaker.
- Build everything as one Python service.
  Rejected because Windows/Linux network probing and local operator deployment
  are stronger with a PowerShell monitor.
