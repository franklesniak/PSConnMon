# PSConnMon Requirements

- **Status:** Active
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-13
- **Scope:** Defines product requirements and roadmap mapping for the PSConnMon
  monitor and reporting service. Does not cover release notes.
- **Related:** [Architecture](architecture.md), [ADR-0001](../adr/ADR-0001-agent-service-architecture.md), [Roadmap](../../PSConnMon_Roadmap.md)

## Summary

This document translates the roadmap into implementable, testable requirements.
Each requirement maps to a roadmap section and keeps the repo's stylistic and
quality constraints explicit.

## Requirements

### PSCONNMON-REQ-001

The system **MUST** expose a PowerShell monitoring module with public commands
for config validation, sample config generation, cycle execution, event writing,
and end-to-end agent execution.

- **Rationale:** The roadmap calls for parameter consolidation, a coherent input
  model, and module packaging.
- **Roadmap Mapping:** `Core Improvements > Parameter Consolidation`,
  `README Roadmap > PowerShell module`
- **Verification:** Pester unit tests and wrapper execution tests.

### PSCONNMON-REQ-002

The system **MUST** use a structured configuration model with top-level sections
`agent`, `publish`, `tests`, `auth`, `targets`, `internetTargets`, and
`extensions`.

- **Rationale:** The roadmap requires structured configuration, multiple targets,
  and command-and-control. Internal hosts and internet probe destinations have
  different operator meaning and **SHOULD NOT** be conflated.
- **Roadmap Mapping:** `Input Model Improvements > JSON-Based Input`,
  `Default Target Behavior`
- **Verification:** Schema file review, PowerShell validation tests, and Python
  contract tests.

### PSCONNMON-REQ-003

The system **MUST** emit structured JSON events with explicit target identity and
normalized result states.

- **Rationale:** Thin CSV rows are insufficient for long-term analysis or a
  PingPlotter-style dashboard.
- **Roadmap Mapping:** `Logging and Telemetry`, `Visualization & Reporting`
- **Verification:** Event schema tests and ingest tests.

### PSCONNMON-REQ-004

The system **MUST** support cross-platform ICMP, DNS, internet-quality, and
traceroute probes, Linux credentialed SMB probing, and a Linux Kerberos
auth-health probe using supported native tooling.

- **Rationale:** Windows and Linux are both first-class target platforms.
- **Roadmap Mapping:** `Multi-Platform Support`, `Authentication Testing`,
  `Network Quality Features`
- **Verification:** Probe unit tests, cross-platform CI, and soak/fault tests.

### PSCONNMON-REQ-005

The system **MUST NOT** stop the full monitoring cycle because one startup
validation or share test fails.

- **Rationale:** Exit logic and failure isolation are explicit roadmap items.
- **Roadmap Mapping:** `Core Improvements > Exit Logic Improvements`
- **Verification:** Pester integration tests covering partial startup failures.

### PSCONNMON-REQ-006

The reporting surface **MUST** ship as a lightweight Python web service using
FastAPI and DuckDB, with a built-in dashboard as the primary operator
experience.

- **Rationale:** The goal is a deployable, lightweight, built-in
  PingPlotter-style reporting surface.
- **Roadmap Mapping:** `Visualization & Reporting`
- **Verification:** pytest API, storage, and dashboard tests.

The dashboard **MUST** render internal monitored hosts and internet targets as
separate queryable entities, and **MUST** support per-target drilldown into the
tests assigned to that target.

### PSCONNMON-REQ-007

The Azure delivery path **MUST** support managed identity for service and agent
access to Storage, with SAS as a documented fallback.

- **Rationale:** The roadmap asks for Azure-backed command-and-control and
  centralized telemetry.
- **Roadmap Mapping:** `Command and Control Model`, `Logging and Telemetry`
- **Verification:** Terraform review, adapter tests, and deployment runbooks.

### PSCONNMON-REQ-008

The reporting service **MUST** support scheduled pull imports from a local
directory, Azure Blob Storage, or both, with idempotent batch tracking in
DuckDB.

- **Rationale:** Deployed monitors cannot assume line-of-sight to the dashboard.
- **Roadmap Mapping:** `Logging and Telemetry`, `Visualization & Reporting`,
  `Open Architecture Questions`
- **Verification:** Import worker tests, dashboard/API tests, and Azurite or
  fake-source integration tests.

### PSCONNMON-REQ-009

The extensibility model **MUST** allow only trusted local PowerShell script
files. Inline script content from YAML, JSON, or Azure-delivered config **MUST
NOT** execute.

- **Rationale:** The roadmap calls for extensibility without weakening the
  repository's input-boundary rules.
- **Roadmap Mapping:** `Extensibility`
- **Verification:** PowerShell config validation tests and extension execution
  tests.

### PSCONNMON-REQ-010

Built-in Linux SMB probing **MUST** support `currentContext`,
`kerberosKeytab`, and `usernamePassword` auth profiles. Secret-backed Linux
profiles **MUST** resolve from trusted local JSON files only, and
`usernamePassword` profiles **MUST** remain SMB-only in v1.

- **Rationale:** Linux SMB parity is operationally useful, but credentialed
  probing must keep the trust boundary explicit and local to the collector.
- **Roadmap Mapping:** `Authentication Testing`
- **Verification:** Documentation review, Linux integration tests, and explicit
  negative-path coverage.

## Style Guardrails

The implementation **MUST** follow these repo rules:

- PowerShell code **MUST** use OTBS, advanced functions, approved verbs, and
  comment-based help.
- Python code **MUST** use explicit contracts, actionable exceptions, and pytest
  coverage for non-trivial logic.
- Durable docs **MUST** include header metadata and testable language.
- All code changes **MUST** be run through `pre-commit run --all-files` before
  commit.
