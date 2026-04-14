
# PSConnMon – Development Roadmap

- **Status:** Active
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-09
- **Scope:** Tracks planned improvements, architectural questions, and feature additions for PSConnMon. Does not cover current functionality or release notes.
- **Related:** [README](README.md), [Requirements](docs/spec/requirements.md), [Architecture](docs/spec/architecture.md)

This document tracks planned improvements, architectural questions, and feature additions for **PSConnMon**.

The goal is to improve reliability, expand platform support, and introduce centralized telemetry and visualization.

Implementation artifacts for the current delivery cycle are tracked in
[`docs/spec/requirements.md`](docs/spec/requirements.md) and
[`docs/spec/architecture.md`](docs/spec/architecture.md). Those documents map
the implementation plan back to this roadmap and keep the repo's
contract-first/style guidance explicit.

---

## Core Improvements

### PSScriptAnalyzer / Improvement Factory

- [x] Update documentation to consistently reference the correct tool name.
- [x] Run **PSScriptAnalyzer** across the project.
- [x] Address analyzer warnings and enforce recommended patterns.
- [x] Establish linting as part of the development workflow.

---

### Exit Logic Improvements

Current behavior may prevent execution if an initial check fails.

Planned improvements:

- [x] Improve exit logic so tests **run regardless of initial checks**.
- [x] Implement a **maximum runtime safeguard**.
- [x] Ensure long-running or stalled tests terminate safely.
- [x] Improve error handling and reporting for failed checks.

---

### Default Target Behavior

The default behavior should support running against **multiple servers**.

Tasks:

- [x] Default execution should support **1–N targets**.
- [x] Ensure output structure includes the **FQDN of each tested server**.
- [x] Avoid generic hostnames in output results.

---

### Parameter Consolidation

Some logic currently differs between connection tests.

Tasks:

- [x] Validate whether **Domain Controller tests vs File Share tests** require different logic.
- [x] Determine whether parameters can be **consolidated into a unified model**.
- [x] Simplify input parameters where possible.

---

### ThreadJob Installation Fix

Update the recommended installation command for the required module.

- [x] Update documentation to use:

```powershell
Install-Module ThreadJob -Scope CurrentUser -AllowClobber
```

Reason:

- `AllowClobber` is required due to conflicting `Start-ThreadJob` commands in some environments.

---

## Input Model Improvements

### JSON-Based Input

Allow PSConnMon to accept **structured configuration input**.

Planned work:

- [x] Extend input model to support **JSON configuration**.
- [x] Support **multiple test targets** via configuration.
- [x] Define a JSON schema for connection tests.

Status note:

- Implemented with v1 decision: YAML is the preferred operator format when
  available; JSON remains a first-class supported format for low-dependency
  automation.

Example concept:

```json
{
  "targets": [
    {
      "type": "dns",
      "server": "dc01.domain.local"
    },
    {
      "type": "fileshare",
      "server": "fs01.domain.local"
    }
  ]
}
```

---

### Command and Control Model

Consider a **centralized configuration approach**.

Concept:

- JSON configuration stored in **Azure Storage Account**
- Agents retrieve test configuration periodically.

Tasks:

- [x] Evaluate **Command & Control model** using Azure Storage.
- [x] Determine configuration polling interval.
- [x] Implement authentication to storage account.

Possible authentication approaches:

- Managed identity
- SAS tokens
- Service principals

---

## Logging and Telemetry

PSConnMon should support both **local logging and centralized telemetry**.

Tasks:

- [x] Implement **local logging**.
- [x] Implement **centralized logging to Azure Storage Account**.
- [x] Define structured log format (JSON preferred).
- [x] Determine logging frequency.

Status note:

- Implemented with v1 decision: Azure Blob Storage is the deployed raw
  telemetry transport, and the reporting service imports batches into DuckDB.

Considerations:

- Real-time publishing (not recommended)
- Publish every **X minutes**

---

## Multi-Platform Support

PSConnMon should support **Windows and Linux environments**.

Tasks:

- [x] Validate functionality on **PowerShell Core**.
- [x] Test functionality on **Linux hosts**.
- [x] Verify cross-platform equivalents for commands such as:
  - DNS testing against **primary DNS server**
  - `Get-ChildItem` file share tests.

---

## Authentication Testing

The original design goal was to test **Windows authentication** under the user's security context.

Linux support introduces challenges.

Open questions:

- [x] How should authentication testing work on **Linux clients**?
- [ ] Can **Passthrough authentication** function from domain-joined Ubuntu systems?
- [ ] Evaluate use of **PowerShell SecretManagement module**.
- [ ] Determine secure credential storage strategy.

Status note:

- Implemented with v1 decision: built-in Linux SMB probing is `currentContext`
  only. Credential-backed Linux parity is deferred pending an approved secret
  storage strategy.

---

## Network Quality Features

Future enhancements for deeper network diagnostics.

### Internet Quality Monitoring

- [x] Implement **internet quality testing**.
- [x] Track **latency over time**.

### Traceroute Hop Tracking

Implement traceroute-based path diagnostics.

Possible features:

- Hop-by-hop latency tracking
- Round-trip time (RTT) measurement
- Path change detection

Goal:

Provide functionality similar to **PingPlotter-style monitoring**.

---

## Extensibility

PSConnMon should support **custom testing logic**.

Tasks:

- [x] Allow users to provide **custom script blocks**.
- [x] Support additional tests without modifying the core module.

Status note:

- Implemented with v1 decision: extensions are trusted local PowerShell script
  files referenced by path. Inline script content from YAML, JSON, or Azure
  config is not supported.

Example concept:

```powershell
Invoke-PSConnMon -CustomTest {
    Test-NetConnection example.com
}
```

---

## Visualization & Reporting

Results should be easily consumable and visualized.

Key question:

> Is **Azure Storage** the best destination for telemetry?

Considerations:

- Azure Storage (tables/blobs)
- Azure Log Analytics
- Time-series database
- Power BI integration

Tasks:

- [x] Determine best platform for visualization.
- [x] Define ingestion format.
- [x] Create example dashboards.

Status note:

- Implemented with v1 decision: DuckDB is the dashboard query store. Azure Blob
  Storage remains the raw telemetry transport. Azure Log Analytics, TSDB, and
  Power BI remain future integrations rather than v1 replacements.

---

## Open Architecture Questions

These topics require further investigation.

- [x] Is Azure Storage the optimal telemetry destination?
- [x] What is the best **result publishing interval**?
- [x] How should configuration distribution work?

Status note:

- These questions are closed for v1 by
  [`ADR-0002`](docs/adr/ADR-0002-telemetry-and-import-topology.md) and
  [`ADR-0003`](docs/adr/ADR-0003-extension-trust-boundary.md).
- [ ] What authentication method should be used for Linux?
- [ ] How should results be structured for long-term analysis?

---

## Style and Quality Notes

All roadmap work **MUST** continue to follow the repo's coding and documentation
guidance:

- PowerShell work **MUST** follow
  [`.github/instructions/powershell.instructions.md`](.github/instructions/powershell.instructions.md)
- Python work **MUST** follow
  [`.github/instructions/python.instructions.md`](.github/instructions/python.instructions.md)
- Documentation work **MUST** follow
  [`.github/instructions/docs.instructions.md`](.github/instructions/docs.instructions.md)
- All commits **MUST** pass `pre-commit run --all-files`

---

## Long-Term Vision

The long-term goal of **PSConnMon** is to provide:

- Lightweight **connectivity monitoring**
- Identity-aware connection testing
- Cross-platform diagnostics
- Centralized telemetry
- Extensible network testing

Potential positioning:

> "A PowerShell-native connectivity monitoring framework for hybrid environments."
