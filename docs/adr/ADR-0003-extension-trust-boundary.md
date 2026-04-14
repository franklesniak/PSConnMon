# ADR-0003 Extension Trust Boundary

- **Status:** Accepted
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-09
- **Scope:** Records the v1 extension execution model and trust boundary. Does
  not prescribe future plugin packaging or signing workflows.
- **Related:** [Architecture](../spec/architecture.md), [Requirements](../spec/requirements.md), [Roadmap](../../PSConnMon_Roadmap.md)
- **Date:** 2026-04-09

## Context

The roadmap calls for extensibility, but PSConnMon also treats all external
input as untrusted. Executing inline script content from YAML, JSON, or
Azure-delivered config would violate that boundary.

## Decision

PSConnMon v1 supports only trusted local PowerShell script files as extension
probes.

- Extension config entries reference a local `path` and optional `entryPoint`.
- Inline script text is not supported.
- Extension scripts must resolve under the config directory or the monitor's
  spool extension directory.
- Extension output is normalized into canonical PSConnMon events.

## Consequences

- Positive: Site-specific probes are possible without editing core module code.
- Positive: The trust boundary remains explicit and reviewable.
- Negative: Remote config cannot deliver arbitrary new script logic by itself.
- Negative: Operators must distribute extension files through their own trusted
  local deployment process.

## Alternatives Considered

- Allow inline script blocks in YAML or JSON.
  Rejected because untrusted config must not execute arbitrary code.
- Load extensions from remote storage automatically.
  Rejected for v1 because it expands the trust boundary beyond reviewed local
  files.
