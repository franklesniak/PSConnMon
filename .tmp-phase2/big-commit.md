# Big-commit anatomy (7718c30)

## Commit header
- SHA: `7718c3055609a053266fe785e64a46b5ea06c914`
- Author: Blake Cherry <bcherry007@gmail.com>
- Date: Thu Apr 9 23:06:10 2026 -0500
- Title: `Address roadmap items v1`

### Full commit message body

Verbatim from `git log -1 --format=%B 7718c30`:

```
Address roadmap items v1
```

(That is the entire message — no body, no trailer, no bullet list. Just the title.)

## Raw diffstat summary

From `git show --stat 7718c30`:

- **Files changed:** 56
- **Insertions:** 6,855
- **Deletions:** 7,079
- **Net:** -224 lines (the big deletion is `Watch-Network.ps1` losing 6,246 lines as it is gutted into the new module)

Per-file stat (verbatim, minus the header):

```
 .dockerignore                                      |   11 +
 .gitignore                                         |    3 +
 .pre-commit-config.yaml                            |   15 +-
 Dockerfile                                         |   20 +
 PSConnMon/PSConnMon.psd1                           |   33 +
 PSConnMon/PSConnMon.psm1                           | 2280 +++++++
 PSConnMon_Roadmap.md                               |  142 +-
 README.md                                          |  383 +-
 Watch-Network.ps1                                  | 6246 +-------------------
 docker-compose.yml                                 |   22 +
 docs/adr/ADR-0001-agent-service-architecture.md    |   44 +
 docs/adr/ADR-0002-telemetry-and-import-topology.md |   47 +
 docs/adr/ADR-0003-extension-trust-boundary.md      |   42 +
 docs/runbooks/demo.md                              |   45 +
 docs/runbooks/troubleshooting.md                   |   40 +
 docs/spec/architecture.md                          |   83 +
 docs/spec/requirements.md                          |  139 +
 infra/terraform/azure/README.md                    |  109 +
 infra/terraform/azure/demo.tfvars                  |   22 +
 infra/terraform/azure/main.tf                      |  172 +
 infra/terraform/azure/outputs.tf                   |   19 +
 infra/terraform/azure/providers.tf                 |   16 +
 infra/terraform/azure/variables.tf                 |  158 +
 pyproject.toml                                     |   55 +-
 samples/config/azure-branch.psconnmon.json         |  100 +
 samples/config/azure-branch.psconnmon.yaml         |   76 +
 samples/config/extensions/Invoke-SampleProbe.ps1   |   16 +
 samples/config/local-lab.psconnmon.json            |   71 +
 samples/config/local-lab.psconnmon.yaml            |   62 +
 samples/ingest/sample-batch.json                   |   81 +
 schemas/psconnmon-config.schema.json               |   64 +
 schemas/psconnmon-event.schema.json                |   83 +
 src/copilot_repo_template/__init__.py              |   25 -
 src/copilot_repo_template/example.py               |   58 -
 src/psconnmon_service/__init__.py                  |    5 +
 src/psconnmon_service/__main__.py                  |   15 +
 src/psconnmon_service/app.py                       |  100 +
 src/psconnmon_service/config.py                    |   71 +
 src/psconnmon_service/importer.py                  |  293 +
 src/psconnmon_service/models.py                    |  183 +
 src/psconnmon_service/storage.py                   |  515 ++
 src/psconnmon_service/ui.py                        |  427 ++
 templates/powershell/Example.Tests.ps1             |  423 --
 templates/python/README.md                         |   34 -
 templates/python/pyproject.toml                    |   79 -
 templates/python/tests/__init__.py                 |    2 -
 templates/python/tests/test_placeholder.py         |   12 -
 tests/PowerShell/PSConnMon.Tests.ps1               |  507 ++
 tests/PowerShell/Placeholder.Tests.ps1             |   34 -
 tests/__init__.py                                  |   10 -
 tests/python/conftest.py                           |   12 +
 tests/python/test_app.py                           |  127 +
 tests/python/test_importer.py                      |  116 +
 tests/python/test_models.py                        |   53 +
 tests/python/test_storage.py                       |   72 +
 tests/test_example.py                              |   62 -
 56 files changed, 6855 insertions(+), 7079 deletions(-)
```

## Grouped file list

The 56 files cluster into these buckets:

### PowerShell module (NEW) — 2 files, 2,313 lines
- `PSConnMon/PSConnMon.psm1` — +2,280
- `PSConnMon/PSConnMon.psd1` — +33 (module manifest)

### PowerShell script (GUTTED) — 1 file, -6,246 lines
- `Watch-Network.ps1` — the prior monolith shrinks by 6,246 lines; its behavior moves into the new module.

### Python service (NEW) — 8 files, 1,609 lines
- `src/psconnmon_service/__init__.py` — +5
- `src/psconnmon_service/__main__.py` — +15
- `src/psconnmon_service/app.py` — +100
- `src/psconnmon_service/config.py` — +71
- `src/psconnmon_service/importer.py` — +293
- `src/psconnmon_service/models.py` — +183
- `src/psconnmon_service/storage.py` — +515
- `src/psconnmon_service/ui.py` — +427

### ADRs (NEW) — 3 files, 133 lines
- `docs/adr/ADR-0001-agent-service-architecture.md` — +44
- `docs/adr/ADR-0002-telemetry-and-import-topology.md` — +47
- `docs/adr/ADR-0003-extension-trust-boundary.md` — +42

### Spec (NEW) — 2 files, 222 lines
- `docs/spec/architecture.md` — +83
- `docs/spec/requirements.md` — +139

### Runbooks (NEW) — 2 files, 85 lines
- `docs/runbooks/demo.md` — +45
- `docs/runbooks/troubleshooting.md` — +40
- Note: `docs/runbooks/distributed-deployment.md` does **not** land here; it arrives later in `ef879ed`.

### Schemas (NEW) — 2 files, 147 lines
- `schemas/psconnmon-config.schema.json` — +64
- `schemas/psconnmon-event.schema.json` — +83

### Samples (NEW) — 6 files, 406 lines
- `samples/config/azure-branch.psconnmon.json` — +100
- `samples/config/azure-branch.psconnmon.yaml` — +76
- `samples/config/local-lab.psconnmon.json` — +71
- `samples/config/local-lab.psconnmon.yaml` — +62
- `samples/config/extensions/Invoke-SampleProbe.ps1` — +16
- `samples/ingest/sample-batch.json` — +81

### Tests (NEW) — 6 files, 887 lines
- `tests/PowerShell/PSConnMon.Tests.ps1` — +507
- `tests/python/conftest.py` — +12
- `tests/python/test_app.py` — +127
- `tests/python/test_importer.py` — +116
- `tests/python/test_models.py` — +53
- `tests/python/test_storage.py` — +72

### Infra (NEW, later removed) — 6 files, 496 lines
- `infra/terraform/azure/README.md` — +109
- `infra/terraform/azure/demo.tfvars` — +22
- `infra/terraform/azure/main.tf` — +172
- `infra/terraform/azure/outputs.tf` — +19
- `infra/terraform/azure/providers.tf` — +16
- `infra/terraform/azure/variables.tf` — +158

### Container & tooling — 5 files
- `Dockerfile` — +20
- `docker-compose.yml` — +22
- `.dockerignore` — +11
- `.gitignore` — +3
- `.pre-commit-config.yaml` — +/- 15
- `pyproject.toml` — +/- 55 (churn, not pure add)

### Docs (top-level) — 2 files
- `README.md` — +/- 383 (large rewrite)
- `PSConnMon_Roadmap.md` — +/- 142

### Template removals — 10 files, 739 deleted lines
- `src/copilot_repo_template/__init__.py` — -25
- `src/copilot_repo_template/example.py` — -58
- `templates/powershell/Example.Tests.ps1` — -423
- `templates/python/README.md` — -34
- `templates/python/pyproject.toml` — -79
- `templates/python/tests/__init__.py` — -2
- `templates/python/tests/test_placeholder.py` — -12
- `tests/PowerShell/Placeholder.Tests.ps1` — -34
- `tests/__init__.py` — -10
- `tests/test_example.py` — -62

## ADR-0001 diff slice (first ~120 lines)

Verbatim from `git show 7718c30 -- docs/adr/ADR-0001-agent-service-architecture.md | head -120` (the file is only 44 lines, so the entire diff fits in the window):

```
commit 7718c3055609a053266fe785e64a46b5ea06c914
Author: Blake Cherry <bcherry007@gmail.com>
Date:   Thu Apr 9 23:06:10 2026 -0500

    Address roadmap items v1

diff --git a/docs/adr/ADR-0001-agent-service-architecture.md b/docs/adr/ADR-0001-agent-service-architecture.md
new file mode 100644
index 0000000..07750e9
--- /dev/null
+++ b/docs/adr/ADR-0001-agent-service-architecture.md
@@ -0,0 +1,44 @@
+# ADR-0001 Agent and Service Split
+
+- **Status:** Accepted
+- **Owner:** Repository Maintainers
+- **Last Updated:** 2026-04-09
+- **Scope:** Records the decision to split PSConnMon into a PowerShell monitor
+  and Python reporting service. Does not prescribe UI polish or release timing.
+- **Related:** [Architecture](../spec/architecture.md), [Requirements](../spec/requirements.md), [Roadmap](../../PSConnMon_Roadmap.md)
+- **Date:** 2026-04-09
+
+## Context
+
+The prior single-script model can collect useful connectivity data, but it is
+not a good fit for reporting, cloud delivery, or independent
+service deployment. The product needs a lightweight operator experience without
+forcing Windows-only hosting for the dashboard tier.
+
+## Decision
+
+PSConnMon will use two deployable components:
+
+- A **PowerShell monitor** for network-adjacent probes, local spooling, and Azure
+  config polling.
+- A **Python reporting service** for ingestion, query, and visualization.
+
+## Consequences
+
+- Positive: The PowerShell side stays close to the network while the dashboard
+  stays easy to containerize.
+- Positive: The reporting UI can use Python web tooling and DuckDB without
+  bloating the monitor.
+- Positive: Azure deployment maps cleanly to Container Apps plus Storage.
+- Negative: The repo now has dual-language build and test responsibilities.
+- Negative: Shared contracts must be maintained carefully between PowerShell and
+  Python.
+
+## Alternatives Considered
+
+- Keep a single PowerShell-only application.
+  Rejected because the built-in dashboard and container delivery would be
+  weaker.
+- Build everything as one Python service.
+  Rejected because Windows/Linux network probing and local operator deployment
+  are stronger with a PowerShell monitor.
```

## Talk-worthy observations

- **One-line commit message, ~14k lines changed.** The entire narrative for a monolith-to-module refactor, a brand-new Python service, three ADRs, a spec, runbooks, schemas, samples, tests, container tooling, and Terraform is compressed into the title "Address roadmap items v1." There is no message body — the ADRs and spec files *are* the narrative. Codex chose to document via artifacts rather than via commit prose.

- **Script-to-module refactor happens in the same commit as the new service.** `Watch-Network.ps1` sheds 6,246 lines while `PSConnMon/PSConnMon.psm1` (+2,280) and `PSConnMon/PSConnMon.psd1` (+33) appear — a single-file PowerShell script becomes a proper module *and* acquires a cross-language sibling (Python service) in one shot. There is no intermediate "just extract the module" commit.

- **ADRs emerge alongside code, not ahead of it.** ADR-0001/0002/0003 land in the same commit that implements the decisions they record. The ADR text is written in the past tense of having already decided ("Status: Accepted", dated 2026-04-09, the same day as the commit). Codex produced the governance artifacts retroactively as part of the implementation sweep rather than as a pre-step.

- **Breadth of one-shot output is unusually wide.** A single commit touches: PowerShell module + manifest, Python package (app/config/importer/models/storage/ui), JSON schemas for both config and events, JSON+YAML sample configs for two deployment shapes (azure-branch, local-lab), an ingest sample batch, Pester tests (+507), pytest suite (~380 across 4 files + conftest), Dockerfile + docker-compose, Terraform for Azure, three ADRs, two spec documents, two runbooks, a 383-line README rewrite, roadmap churn, and pre-commit/pyproject updates. That is roughly 10 distinct concerns in a single atomic change.

- **Docker + Terraform chosen unprompted at the very first implementation step.** The Azure Container Apps + Storage deployment target is asserted in ADR-0001 ("Azure deployment maps cleanly to Container Apps plus Storage") and then immediately backed by `Dockerfile`, `docker-compose.yml`, and a full `infra/terraform/azure/` module (main/variables/outputs/providers + README + demo.tfvars, 496 lines). Notably this Terraform is **removed later** — the agent over-committed to cloud infra in v1 and subsequently walked it back.

- **Template scaffolding is removed in the same commit that replaces it.** `src/copilot_repo_template/`, `templates/powershell/Example.Tests.ps1` (-423), `templates/python/*`, `tests/PowerShell/Placeholder.Tests.ps1`, `tests/__init__.py`, and `tests/test_example.py` are all deleted simultaneously with the real code landing. Codex does not leave placeholder files sitting alongside the real implementation — the repo transitions from "template" to "product" atomically.

- **Test coverage is produced alongside the implementation, not after.** Both the Pester suite (`PSConnMon.Tests.ps1`, 507 lines) and the pytest suite (~380 lines across test_app/test_importer/test_models/test_storage + conftest) appear in the same commit as the code they cover. There is no "implement now, tests later" pattern.

- **The delta is net-negative in lines (-224)** despite introducing an entire second runtime. The monolith's 6,246-line deletion dominates — Codex compressed the script into ~2,280 lines of module code plus ~1,609 lines of Python service, and still came out ahead. That is the signature of a genuine refactor, not just additive accretion.
