# ADR extractor output

## Summary table
| Number | Title | Status | Date | One-sentence decision |
|---|---|---|---|---|
| ADR-0001 | Agent and Service Split | Accepted | 2026-04-09 | Split PSConnMon into a PowerShell monitor (network probes, spooling, Azure config polling) and a Python reporting service (ingestion, query, visualization). |
| ADR-0002 | Telemetry and Import Topology | Accepted | 2026-04-09 | Monitors write canonical JSONL batches locally and optionally upload to Azure Blob Storage; the reporting service pulls from local dir and/or Blob into DuckDB, with direct HTTP ingest kept only for manual seeding and tests. |
| ADR-0003 | Extension Trust Boundary | Accepted | 2026-04-09 | v1 extension probes must be trusted local PowerShell script files referenced by path under the config or spool extension directory; inline script text and remote script delivery are disallowed. |

## ADR-0001 — Agent and Service Split
- **Status:** Accepted
- **Owner:** Repository Maintainers
- **Last Updated / Date:** 2026-04-09
- **Scope:** Records the decision to split PSConnMon into a PowerShell monitor and a Python reporting service. Does not prescribe UI polish or release timing.
- **Context (bullets):**
  - The prior single-script model can collect useful connectivity data.
  - That single-script model is a poor fit for reporting, cloud delivery, or independent service deployment.
  - The product needs a lightweight operator experience.
  - The dashboard tier must not be forced to run Windows-only hosting.
- **Decision quote (verbatim):**
  > PSConnMon will use two deployable components:
  >
  > - A **PowerShell monitor** for network-adjacent probes, local spooling, and Azure
  >   config polling.
  > - A **Python reporting service** for ingestion, query, and visualization.
- **Consequences (verbatim bullets):**
  - Positive: The PowerShell side stays close to the network while the dashboard stays easy to containerize.
  - Positive: The reporting UI can use Python web tooling and DuckDB without bloating the monitor.
  - Positive: Azure deployment maps cleanly to Container Apps plus Storage.
  - Negative: The repo now has dual-language build and test responsibilities.
  - Negative: Shared contracts must be maintained carefully between PowerShell and Python.
- **Alternatives considered:**
  - Keep a single PowerShell-only application — rejected because the built-in dashboard and container delivery would be weaker.
  - Build everything as one Python service — rejected because Windows/Linux network probing and local operator deployment are stronger with a PowerShell monitor.

## ADR-0002 — Telemetry and Import Topology
- **Status:** Accepted
- **Owner:** Repository Maintainers
- **Last Updated / Date:** 2026-04-09
- **Scope:** Records the v1 telemetry transport, import topology, and dashboard data-store decision. Does not prescribe future analytics integrations.
- **Context (bullets):**
  - PSConnMon needs a central reporting path.
  - Monitors should not have to reach the dashboard directly.
  - The product needs a lightweight query store.
  - The query store must run locally and in a simple container.
- **Decision quote (verbatim):**
  > PSConnMon v1 uses this topology:
  >
  > - Monitors write canonical JSONL batches locally.
  > - Monitors can upload those batches to Azure Blob Storage.
  > - The reporting service pulls batches from a local directory, Azure Blob
  >   Storage, or both.
  > - DuckDB is the dashboard query store.
  > - Direct HTTP ingest remains available for manual seeding and tests, but it is
  >   not the primary deployed telemetry path.
- **Consequences (verbatim bullets):**
  - Positive: Deployed monitors do not need line-of-sight to the dashboard.
  - Positive: Azure Blob Storage serves as a simple raw telemetry transport and archive.
  - Positive: DuckDB keeps the service lightweight and easy to deploy.
  - Negative: Import freshness and idempotency must be tracked explicitly.
  - Negative: Azure-native analytics backends are deferred rather than built in.
- **Alternatives considered:**
  - Require each agent to post directly to the dashboard — rejected because network reachability and firewall posture are too brittle.
  - Use Azure Log Analytics or a dedicated time-series database as the primary store — rejected for v1 because deployment weight and cost model are higher than necessary.
  - Query Azure Blob Storage directly from the dashboard — rejected because the UI should read from DuckDB only.

## ADR-0003 — Extension Trust Boundary
- **Status:** Accepted
- **Owner:** Repository Maintainers
- **Last Updated / Date:** 2026-04-09
- **Scope:** Records the v1 extension execution model and trust boundary. Does not prescribe future plugin packaging or signing workflows.
- **Context (bullets):**
  - The roadmap calls for extensibility.
  - PSConnMon treats all external input as untrusted.
  - Executing inline script content from YAML, JSON, or Azure-delivered config would violate that trust boundary.
- **Decision quote (verbatim):**
  > PSConnMon v1 supports only trusted local PowerShell script files as extension
  > probes.
  >
  > - Extension config entries reference a local `path` and optional `entryPoint`.
  > - Inline script text is not supported.
  > - Extension scripts must resolve under the config directory or the monitor's
  >   spool extension directory.
  > - Extension output is normalized into canonical PSConnMon events.
- **Consequences (verbatim bullets):**
  - Positive: Site-specific probes are possible without editing core module code.
  - Positive: The trust boundary remains explicit and reviewable.
  - Negative: Remote config cannot deliver arbitrary new script logic by itself.
  - Negative: Operators must distribute extension files through their own trusted local deployment process.
- **Alternatives considered:**
  - Allow inline script blocks in YAML or JSON — rejected because untrusted config must not execute arbitrary code.
  - Load extensions from remote storage automatically — rejected for v1 because it expands the trust boundary beyond reviewed local files.

## Cross-cutting observations
- All three ADRs share an identical frontmatter shape (Status / Owner / Last Updated / Scope / Related / Date), all are dated 2026-04-09, all are owned by "Repository Maintainers," and all explicitly scope themselves to v1 while deferring forward-looking concerns — suggesting a deliberate, template-driven ADR practice.
- The architecture vocabulary is consistent across the set: "monitor" (PowerShell, network-adjacent), "reporting service" (Python), "canonical JSONL batches / canonical PSConnMon events," "spool," "Azure Blob Storage," "DuckDB," "config directory / spool extension directory," and an explicit "trust boundary." Together they describe a spool-and-pull pipeline rather than a push-to-dashboard pipeline.
- There is a strong, repeated bias toward minimizing deployment weight and coupling: ADR-0001 splits languages along deployment fit lines, ADR-0002 rejects heavier analytics backends and direct HTTP push, and ADR-0003 rejects remote code delivery — each decision trades capability for operability and reviewability.
- Security posture is load-bearing and cross-cuts the telemetry and extension decisions: ADR-0003 explicitly invokes the "all external input is untrusted" rule (echoing the repository constitution in CLAUDE.md / copilot-instructions), and ADR-0002's rejection of direct dashboard ingest aligns with that firewall/trust posture.
- Each ADR carefully states what it does *not* decide (UI polish and release timing; future analytics integrations; future plugin packaging or signing), showing a disciplined separation between architectural commitment and open design space — leaving clear hooks for future ADRs (e.g., signed extensions, Azure-native analytics) without pre-committing.
