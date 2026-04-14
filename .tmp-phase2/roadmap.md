# Roadmap extractor output

## File metadata
- Path: `PSConnMon_Roadmap.md`
- Approximate line count: 328
- Document version / header block (if present):
  - **Status:** Active
  - **Owner:** Repository Maintainers
  - **Last Updated:** 2026-04-09
  - **Scope:** Tracks planned improvements, architectural questions, and feature additions for PSConnMon. Does not cover current functionality or release notes.
  - **Related:** README, Requirements (`docs/spec/requirements.md`), Architecture (`docs/spec/architecture.md`)
- Earliest/latest commit referenced (header block only): None. The header block contains no commit SHAs — only a "Last Updated" date (2026-04-09) and links to related docs.

## Top-level structure
All `##` headings in document order:

1. `## Core Improvements`
2. `## Input Model Improvements`
3. `## Logging and Telemetry`
4. `## Multi-Platform Support`
5. `## Authentication Testing`
6. `## Network Quality Features`
7. `## Extensibility`
8. `## Visualization & Reporting`
9. `## Open Architecture Questions`
10. `## Style and Quality Notes`
11. `## Long-Term Vision`

(Note: there are numerous `###` subheadings beneath these — e.g. PSScriptAnalyzer / Improvement Factory, Exit Logic Improvements, Default Target Behavior, Parameter Consolidation, ThreadJob Installation Fix, JSON-Based Input, Command and Control Model, Internet Quality Monitoring, Traceroute Hop Tracking — but the request was for `##` headings only.)

## Phases / major sections

- **Core Improvements** — Foundational hygiene work: PSScriptAnalyzer adoption, exit/runtime safeguards, multi-target default behavior, parameter consolidation across DC vs. file share tests, and a ThreadJob install-command documentation fix. All checkboxes in this section are marked done.
- **Input Model Improvements** — Introduces JSON-based structured configuration and a centralized "Command and Control" model backed by Azure Storage with polling agents. Contains **1** "Implemented with v1 decision" callout (YAML preferred, JSON remains first-class).
- **Logging and Telemetry** — Local logging plus centralized telemetry to Azure Storage with a structured (JSON-preferred) log format and a defined publish cadence. Contains **1** "Implemented with v1 decision" callout (Azure Blob Storage is the raw transport; reporting service imports batches into DuckDB).
- **Multi-Platform Support** — Validate PowerShell Core, Linux host functionality, and cross-platform equivalents for DNS and file share checks. All tasks marked done.
- **Authentication Testing** — Original design goal was Windows auth under the user's security context; Linux introduces complexity around passthrough auth, SecretManagement, and secure credential storage. Contains **1** "Implemented with v1 decision" callout plus open unchecked items.
- **Network Quality Features** — Future depth: internet quality/latency trending and traceroute-style hop/RTT/path-change tracking ("PingPlotter-style monitoring"). Some tasks checked, traceroute features listed as possible features (no checkboxes).
- **Extensibility** — Custom script block support so users can add tests without modifying the core module. Contains **1** "Implemented with v1 decision" callout (extensions are trusted local PowerShell files by path; inline script content from YAML/JSON/Azure config is not supported).
- **Visualization & Reporting** — Picks the telemetry destination and visualization platform; considers Azure Storage, Log Analytics, TSDB, Power BI. Contains **1** "Implemented with v1 decision" callout (DuckDB is the dashboard query store; Azure Blob is raw transport; Log Analytics/TSDB/Power BI are future integrations).
- **Open Architecture Questions** — Lists cross-cutting questions; marks three as closed-for-v1 via ADR-0002 and ADR-0003, and leaves two open (Linux auth method, long-term result structure).
- **Style and Quality Notes** — Mandates the three language instruction files and `pre-commit run --all-files`.
- **Long-Term Vision** — Positioning and bullet list of product goals (lightweight connectivity monitoring, identity-aware testing, cross-platform, centralized telemetry, extensibility).

**Status callout count:** 5 "Implemented with v1 decision" blocks (Input Model, Logging/Telemetry, Authentication, Extensibility, Visualization) plus 1 aggregate "closed for v1 by ADR" block in Open Architecture Questions.

## Status callouts

Verbatim quotations with their surrounding bullet context:

1. JSON-Based Input:
   > Status note:
   >
   > - Implemented with v1 decision: YAML is the preferred operator format when
   >   available; JSON remains a first-class supported format for low-dependency
   >   automation.

2. Logging and Telemetry:
   > Status note:
   >
   > - Implemented with v1 decision: Azure Blob Storage is the deployed raw
   >   telemetry transport, and the reporting service imports batches into DuckDB.

3. Authentication Testing:
   > Status note:
   >
   > - Implemented with v1 decision: built-in Linux SMB probing is `currentContext`
   >   only. Credential-backed Linux parity is deferred pending an approved secret
   >   storage strategy.

4. Extensibility:
   > Status note:
   >
   > - Implemented with v1 decision: extensions are trusted local PowerShell script
   >   files referenced by path. Inline script content from YAML, JSON, or Azure
   >   config is not supported.

5. Visualization & Reporting:
   > Status note:
   >
   > - Implemented with v1 decision: DuckDB is the dashboard query store. Azure Blob
   >   Storage remains the raw telemetry transport. Azure Log Analytics, TSDB, and
   >   Power BI remain future integrations rather than v1 replacements.

6. Open Architecture Questions (closed-for-v1 aggregate + still-open items):
   > Status note:
   >
   > - These questions are closed for v1 by
   >   [`ADR-0002`](docs/adr/ADR-0002-telemetry-and-import-topology.md) and
   >   [`ADR-0003`](docs/adr/ADR-0003-extension-trust-boundary.md).
   > - [ ] What authentication method should be used for Linux?
   > - [ ] How should results be structured for long-term analysis?

7. Authentication Testing — explicit "Open questions" list with remaining unchecked items:
   > Open questions:
   >
   > - [x] How should authentication testing work on **Linux clients**?
   > - [ ] Can **Passthrough authentication** function from domain-joined Ubuntu systems?
   > - [ ] Evaluate use of **PowerShell SecretManagement module**.
   > - [ ] Determine secure credential storage strategy.

Note: the document does not use the literal strings "Deferred" (except the word "deferred" in the Authentication callout quoted above: "Credential-backed Linux parity is deferred …") or "TBD". The phrase "Open question" appears as a section heading ("Open questions:") in Authentication Testing and as `## Open Architecture Questions`.

## Verbatim excerpts

Excerpt 1 — opening Purpose/Scope block:

> # PSConnMon – Development Roadmap
>
> - **Status:** Active
> - **Owner:** Repository Maintainers
> - **Last Updated:** 2026-04-09
> - **Scope:** Tracks planned improvements, architectural questions, and feature additions for PSConnMon. Does not cover current functionality or release notes.
> - **Related:** [README](README.md), [Requirements](docs/spec/requirements.md), [Architecture](docs/spec/architecture.md)
>
> This document tracks planned improvements, architectural questions, and feature additions for **PSConnMon**.
>
> The goal is to improve reliability, expand platform support, and introduce centralized telemetry and visualization.

Excerpt 2 — Command and Control phase-definition block:

> ### Command and Control Model
>
> Consider a **centralized configuration approach**.
>
> Concept:
>
> - JSON configuration stored in **Azure Storage Account**
> - Agents retrieve test configuration periodically.
>
> Tasks:
>
> - [x] Evaluate **Command & Control model** using Azure Storage.
> - [x] Determine configuration polling interval.
> - [x] Implement authentication to storage account.

Excerpt 3 — Visualization decision rationale / key question:

> ## Visualization & Reporting
>
> Results should be easily consumable and visualized.
>
> Key question:
>
> > Is **Azure Storage** the best destination for telemetry?
>
> Considerations:
>
> - Azure Storage (tables/blobs)
> - Azure Log Analytics
> - Time-series database
> - Power BI integration

## Cross-references

- **ADR references:**
  - `ADR-0002` — `docs/adr/ADR-0002-telemetry-and-import-topology.md`, referenced in the "Open Architecture Questions" status note (around line 294).
  - `ADR-0003` — `docs/adr/ADR-0003-extension-trust-boundary.md`, referenced in the same status note (around line 295).
  - No other ADR numbers appear in the document.

- **`.github/instructions/` references** (all in the "Style and Quality Notes" section, ~lines 306–311):
  - `.github/instructions/powershell.instructions.md`
  - `.github/instructions/python.instructions.md`
  - `.github/instructions/docs.instructions.md`

- **Module / package / infra references:**
  - **PSConnMon module:** Referenced throughout (title, long-term vision, `Invoke-PSConnMon` example around line 247).
  - **psconnmon_service Python package:** Not referenced by that name. The document mentions a generic "reporting service" that "imports batches into DuckDB" (Logging and Telemetry status note) but does not name the Python package.
  - **infra/terraform/:** Not referenced.
  - **schemas/:** Not referenced by path. The document does mention "Define a JSON schema for connection tests" as a task (JSON-Based Input section) but does not reference a `schemas/` directory.
  - **samples/:** Not referenced.
  - Other referenced docs: `README.md`, `docs/spec/requirements.md`, `docs/spec/architecture.md` (all in the header "Related" line and the intro paragraph at lines 14–18).
