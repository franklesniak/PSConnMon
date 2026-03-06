
# PSConnMon – Development Roadmap & Conference Readiness

This document tracks planned improvements, architectural questions, and feature additions required before presenting **PSConnMon** at a conference.

The goal is to improve reliability, expand platform support, and introduce centralized telemetry and visualization.

---

# Core Improvements

## PSScriptAnalyzer / Improvement Factory

- [ ] Update documentation to consistently reference the correct tool name.
- [ ] Run **PSScriptAnalyzer** across the project.
- [ ] Address analyzer warnings and enforce recommended patterns.
- [ ] Establish linting as part of the development workflow.

---

## Exit Logic Improvements

Current behavior may prevent execution if an initial check fails.

Planned improvements:

- [ ] Improve exit logic so tests **run regardless of initial checks**.
- [ ] Implement a **maximum runtime safeguard**.
- [ ] Ensure long-running or stalled tests terminate safely.
- [ ] Improve error handling and reporting for failed checks.

---

## Default Target Behavior

The default behavior should support running against **multiple servers**.

Tasks:

- [ ] Default execution should support **1–N targets**.
- [ ] Ensure output structure includes the **FQDN of each tested server**.
- [ ] Avoid generic hostnames in output results.

---

## Parameter Consolidation

Some logic currently differs between connection tests.

Tasks:

- [ ] Validate whether **Domain Controller tests vs File Share tests** require different logic.
- [ ] Determine whether parameters can be **consolidated into a unified model**.
- [ ] Simplify input parameters where possible.

---

## ThreadJob Installation Fix

Update the recommended installation command for the required module.

- [ ] Update documentation to use:

```powershell
Install-Module ThreadJob -Scope CurrentUser -AllowClobber
```

Reason:

- `AllowClobber` is required due to conflicting `Start-ThreadJob` commands in some environments.

---

# Input Model Improvements

## JSON-Based Input

Allow PSConnMon to accept **structured configuration input**.

Planned work:

- [ ] Extend input model to support **JSON configuration**.
- [ ] Support **multiple test targets** via configuration.
- [ ] Define a JSON schema for connection tests.

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

## Command and Control Model

Consider a **centralized configuration approach**.

Concept:

- JSON configuration stored in **Azure Storage Account**
- Agents retrieve test configuration periodically.

Tasks:

- [ ] Evaluate **Command & Control model** using Azure Storage.
- [ ] Determine configuration polling interval.
- [ ] Implement authentication to storage account.

Possible authentication approaches:

- Managed identity
- SAS tokens
- Service principals

---

# Logging and Telemetry

PSConnMon should support both **local logging and centralized telemetry**.

Tasks:

- [ ] Implement **local logging**.
- [ ] Implement **centralized logging to Azure Storage Account**.
- [ ] Define structured log format (JSON preferred).
- [ ] Determine logging frequency.

Considerations:

- Real-time publishing (not recommended)
- Publish every **X minutes**

---

# Multi-Platform Support

PSConnMon should support **Windows and Linux environments**.

Tasks:

- [ ] Validate functionality on **PowerShell Core**.
- [ ] Test functionality on **Linux hosts**.
- [ ] Verify cross-platform equivalents for commands such as:
  - DNS testing against **primary DNS server**
  - `Get-ChildItem` file share tests.

---

# Authentication Testing

The original design goal was to test **Windows authentication** under the user's security context.

Linux support introduces challenges.

Open questions:

- [ ] How should authentication testing work on **Linux clients**?
- [ ] Can **Passthrough authentication** function from domain-joined Ubuntu systems?
- [ ] Evaluate use of **PowerShell SecretManagement module**.
- [ ] Determine secure credential storage strategy.

---

# Network Quality Features

Future enhancements for deeper network diagnostics.

## Internet Quality Monitoring

- [ ] Implement **internet quality testing**.
- [ ] Track **latency over time**.

## Traceroute Hop Tracking

Implement traceroute-based path diagnostics.

Possible features:

- Hop-by-hop latency tracking
- Round-trip time (RTT) measurement
- Path change detection

Goal:

Provide functionality similar to **PingPlotter-style monitoring**.

---

# Extensibility

PSConnMon should support **custom testing logic**.

Tasks:

- [ ] Allow users to provide **custom script blocks**.
- [ ] Support additional tests without modifying the core module.

Example concept:

```powershell
Invoke-PSConnMon -CustomTest {
    Test-NetConnection example.com
}
```

---

# Visualization & Reporting

Results should be easily consumable and visualized.

Key question:

> Is **Azure Storage** the best destination for telemetry?

Considerations:

- Azure Storage (tables/blobs)
- Azure Log Analytics
- Time-series database
- Power BI integration

Tasks:

- [ ] Determine best platform for visualization.
- [ ] Define ingestion format.
- [ ] Create example dashboards.

---

# Open Architecture Questions

These topics require further investigation.

- [ ] Is Azure Storage the optimal telemetry destination?
- [ ] What is the best **result publishing interval**?
- [ ] How should configuration distribution work?
- [ ] What authentication method should be used for Linux?
- [ ] How should results be structured for long-term analysis?

---

# Long-Term Vision

The long-term goal of **PSConnMon** is to provide:

- Lightweight **connectivity monitoring**
- Identity-aware connection testing
- Cross-platform diagnostics
- Centralized telemetry
- Extensible network testing

Potential positioning:

> "A PowerShell-native connectivity monitoring framework for hybrid environments."
