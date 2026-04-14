# Spec extractor output

## architecture.md
- **Line count:** 92
- **Section headings (all `##` and `###`):**
  - `## Context`
  - `## System Overview`
  - `## Deployment Diagram`
  - `## Data Flow`
  - `## Roadmap Mapping`
  - `## Failure Modes`
  - `## Open Questions`
- **System overview (1-2 paragraph paraphrase):** PSConnMon is built around a PowerShell monitor that reads YAML/JSON config, runs probe cycles, emits JSONL batch files (optionally mirrored to CSV), can resolve trusted local Linux SMB secret files, and can poll Azure Storage for updated config. Its target model splits internal monitored hosts from agent-scoped `internetTargets` so internet-quality/traceroute telemetry can be queried independently from host reachability.
  A Python reporting service imports batches from local storage and/or Azure Blob Storage, stores hot data in DuckDB, and renders a built-in dashboard plus APIs with separate internal/internet target views and per-target drilldowns. Azure Storage hosts versioned config blobs and raw telemetry uploads for centralized aggregation.
- **Data flow (numbered list, verbatim or tight paraphrase):**
  1. Operator defines config in canonical YAML/JSON schema including internal `targets` and optional `internetTargets`.
  2. PowerShell monitor validates config and executes a monitoring cycle.
  3. Probes emit canonical events into a pending JSONL batch.
  4. Reporting service imports `.jsonl` batches from a local directory, Azure Blob Storage, or both.
  5. DuckDB serves the dashboard and summary APIs.
  6. `POST /api/v1/ingest/batches` remains available for manual seeding and test workflows.
  7. When enabled, Azure Storage holds raw batch uploads and remotely managed config blobs.
- **Failure modes (list, verbatim or tight paraphrase):**
  - A failed share probe MUST NOT stop ping, DNS, traceroute, or internet quality probes.
  - Missing Linux dependencies MUST emit `SKIPPED` events rather than crash the cycle.
  - Linux secret and keytab paths MUST stay under the config directory or the monitor spool secrets directory.
  - Azure config poll failures MUST keep the last-known-good config active.
  - Azure upload failures MUST retain pending batches locally for retry.
  - Import failures MUST be recorded in DuckDB without partially committing an invalid batch.
  - Dashboard rendering MUST read from DuckDB only; it does not read the monitor spool or blob storage directly.
- **Roadmap mapping table (verbatim):**

  | Architecture Element | Roadmap Mapping |
  | --- | --- |
  | Module-based agent | `Parameter Consolidation`, `PowerShell module` |
  | Structured config schema | `JSON-Based Input`, `Command and Control Model` |
  | JSON event batches | `Logging and Telemetry`, `Visualization & Reporting` |
  | Cross-platform probe adapters | `Multi-Platform Support`, `Authentication Testing`, `Network Quality Features` |
  | Internet target split | `Default Target Behavior`, `Visualization & Reporting` |
  | Built-in dashboard | `Visualization & Reporting` |
  | Azure Storage control plane | `Command and Control Model`, `Open Architecture Questions` |

- **Key verbatim quote (5-10 lines):**
  > - **PowerShell monitor:** Reads YAML or JSON config, runs probe cycles, writes
  >   JSONL batch files, optionally mirrors CSV, can resolve trusted local Linux
  >   SMB secret files, and can poll Azure Storage for updated config.
  > - **Structured target model:** Separates internal monitored hosts from
  >   agent-scoped `internetTargets`, so internet-quality and traceroute telemetry
  >   can be queried independently from host reachability.
  > - **Python reporting service:** Imports batches from local storage and Azure
  >   Blob Storage, stores hot data in DuckDB, and renders the built-in dashboard
  >   and APIs with separate internal/internet target views and per-target
  >   drilldowns.

## requirements.md
- **Line count:** 146
- **Section headings:**
  - `## Summary`
  - `## Requirements`
  - `### PSCONNMON-REQ-001`
  - `### PSCONNMON-REQ-002`
  - `### PSCONNMON-REQ-003`
  - `### PSCONNMON-REQ-004`
  - `### PSCONNMON-REQ-005`
  - `### PSCONNMON-REQ-006`
  - `### PSCONNMON-REQ-007`
  - `### PSCONNMON-REQ-008`
  - `### PSCONNMON-REQ-009`
  - `### PSCONNMON-REQ-010`
  - `## Style Guardrails`
- **Functional requirement buckets:**
  - **Agent / PowerShell monitor (REQ-001, REQ-002, REQ-004, REQ-005):**
    - MUST expose a PowerShell monitoring module with public commands for config validation, sample config generation, cycle execution, event writing, and end-to-end agent execution.
    - MUST use a structured configuration model with top-level sections `agent`, `publish`, `tests`, `auth`, `targets`, `internetTargets`, `extensions`.
    - MUST support cross-platform ICMP, DNS, internet-quality, traceroute probes, Linux credentialed SMB probing, and a Linux Kerberos auth-health probe using supported native tooling.
    - MUST NOT stop the full monitoring cycle because one startup validation or share test fails.
  - **Events / telemetry (REQ-003):**
    - MUST emit structured JSON events with explicit target identity and normalized result states (replacing thin CSV rows for durable analysis and a PingPlotter-style dashboard).
  - **Reporting service / dashboard (REQ-006, REQ-008):**
    - Reporting surface MUST ship as a lightweight Python web service using FastAPI + DuckDB with a built-in dashboard as the primary operator experience.
    - Dashboard MUST render internal monitored hosts and internet targets as separate queryable entities with per-target drilldown into assigned tests.
    - MUST support scheduled pull imports from local directory, Azure Blob Storage, or both, with idempotent batch tracking in DuckDB.
  - **Azure integration (REQ-007):**
    - Azure delivery path MUST support managed identity for service and agent access to Storage, with SAS as a documented fallback.
  - **Security / extensibility (REQ-009, REQ-010):**
    - Extensibility MUST allow only trusted local PowerShell script files; inline script content from YAML/JSON/Azure-delivered config MUST NOT execute.
    - Built-in Linux SMB probing MUST support `currentContext`, `kerberosKeytab`, and `usernamePassword` auth profiles; secret-backed Linux profiles MUST resolve from trusted local JSON files only; `usernamePassword` profiles MUST remain SMB-only in v1.
- **Non-functional requirement highlights:**
  - PowerShell code MUST use OTBS, advanced functions, approved verbs, and comment-based help.
  - Python code MUST use explicit contracts, actionable exceptions, and pytest coverage for non-trivial logic.
  - Durable docs MUST include header metadata and testable language.
  - All code changes MUST be run through `pre-commit run --all-files` before commit.
  - Each requirement declares a Verification approach (Pester tests, pytest, schema/contract tests, CI, soak/fault tests, Azurite integration, runbook/Terraform review).
  - Each requirement declares an explicit Roadmap Mapping, preserving traceability from product roadmap to implementable/testable requirements.
- **Key verbatim quote (5-10 lines):**
  > ### PSCONNMON-REQ-009
  >
  > The extensibility model **MUST** allow only trusted local PowerShell script
  > files. Inline script content from YAML, JSON, or Azure-delivered config **MUST
  > NOT** execute.
  >
  > - **Rationale:** The roadmap calls for extensibility without weakening the
  >   repository's input-boundary rules.
  > - **Roadmap Mapping:** `Extensibility`
  > - **Verification:** PowerShell config validation tests and extension execution
  >   tests.

## Cross-cutting observations
- The two files are tightly coupled: `architecture.md` describes the target system shape and `requirements.md` restates the same capabilities as numbered, testable MUST/MUST NOT statements. Both carry identical header metadata (Status Active, Owner "Repository Maintainers", Last Updated 2026-04-13) and cross-link each other plus ADR-0001 and the Roadmap.
- Shared vocabulary includes: `agent` / PowerShell monitor, `importer` / import worker, `DuckDB` storage, FastAPI `dashboard`/UI, `internal targets` vs `internetTargets`, `JSONL batch`, `Azure Storage` / Blob / managed identity / SAS, `extensions`, `Linux SMB` / Kerberos / keytab. This vocabulary matches the ADR-0001 agent-service split and the roadmap buckets cited in the "Roadmap Mapping" table and REQ "Roadmap Mapping" fields.
- Both documents appear human-curated with consistent style (RFC-2119 MUST/SHOULD capitalization, roadmap-cross-reference conventions, mermaid diagram, explicit Verification sections). They read as authored/edited by maintainers rather than dumped by an agent, though the uniform structure is consistent with template-driven authoring.
- Consistency is strong: the failure modes in architecture.md map cleanly to REQ-005 (cycle resilience), REQ-008 (idempotent imports), REQ-007 (Azure auth), and REQ-009/REQ-010 (trust boundaries). No contradictions were found between the two files.
- Minor gap: architecture.md's "Open Questions" flags Linux Kerberos environment validation and deferred Azure auth methods (service principals, connection strings); requirements.md does not have a matching open-question section, so those unknowns live only in the architecture doc and implicitly constrain REQ-004 and REQ-007.
