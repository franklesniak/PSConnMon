<!-- markdownlint-disable MD013 -->

# PSConnMon — Phase 2 Journey Notes

Phase 1 closed with a hardened, single-file `Monitor-Network.ps1` that Frank had
shaped through iterative chat sessions with several LLMs — no coding agent, no
repository scaffolding, just a working script honed by conversation. Phase 2
set out to transform that script into a reusable `PSConnMon` repository using
agentic tooling: first the GitHub Copilot coding agent paired with the Copilot
Code Reviewer for function-by-function style-guide cleanup, then OpenAI Codex
to plan and land a full roadmap — PowerShell module, Python service, dashboard,
deployment story, ADRs, and runbooks.

The timeline below is anchored to real commit SHAs, ADR numbers, and file paths
in this repo.

## Phase E — Function-by-function style-guide cleanup with Copilot agents


### Phase E — Function-by-function style-guide cleanup with Copilot coding agent + Copilot Code Reviewer

Before the in-person Chicago sync, Frank took the Phase 1 `Monitor-Network.ps1` and ran a function-by-function LLM-based audit against his PowerShell style guide. The audit produced a backlog of GitHub Issues (one pair per function: style-guide assessment + remediation tasks). Each issue was then picked up by GitHub Copilot's coding agent, implemented on a `copilot/**` branch, and pushed through a multi-round review loop with GitHub Copilot Code Reviewer — Frank acting as the human-in-the-loop adjudicator.

- **Stage purpose** — Convert the Phase 1 script from "works" to "conforms to the repo's PowerShell style guide" without Frank hand-editing every function, by outsourcing the mechanical rewrites to the Copilot coding agent under a formal review protocol.
- **What changed** —
  - A function-by-function style-guide audit (run externally) generated a per-function backlog of GitHub Issues, each assigned to the Copilot coding agent for implementation and then to Copilot Code Reviewer for review.
  - **Evidence gap in this repo:** the backlog-generator GitHub Actions workflow lives in a *private* repo and is **not** reproduced here. The five workflows visible under `.github/workflows/` are `check-placeholders.yml`, `auto-fix-precommit.yml`, `python-ci.yml`, `powershell-ci.yml`, and `markdownlint.yml` — no backlog-generation pipeline among them.
  - The *posture* that enabled this loop does ship in this repo as an instruction-file template: `CLAUDE.md` v1.2.20260414.0, `AGENTS.md` v1.1.20260412.1 (for Codex), and `GEMINI.md` v1.1.20260412.1 each defer to `.github/copilot-instructions.md` v1.1.20260112.0, which is explicitly declared the "repo-wide constitution."
  - Three per-language style guides under `.github/instructions/` — `docs.instructions.md`, `powershell.instructions.md` (v2.7.20260414.0), and `python.instructions.md` — are what the Copilot coding agent is told to conform to. PowerShell is the one that matters for `Monitor-Network.ps1`; it tags every rule `[All]`, `[Modern]`, or `[v1.0]` so Frank's PS 5.1 compatibility stays intact through the rewrites.
  - `auto-fix-precommit.yml` is the CI safety net specifically for `copilot/**` branches: when the Copilot coding agent pushes code that fails `pre-commit run --all-files`, CI runs the hooks and auto-commits the fixes so the PR stays green. Pre-commit is effectively enforced **twice** — once locally per the constitution, once in CI as a dedicated coding-agent backstop.
  - Pre-mega Copilot-coding-agent activity visible in *this* repo's history shows the same issue-to-PR-to-review cadence applied to template-shakedown tasks rather than Phase 1 functions: commits `0fc30fb` and `b2ba923` (both "Initial plan" by `copilot-swe-agent[bot]`), `62a5f97` "Remove Terraform support and replace template placeholders", `abb801a` "Replace public Discussions link with private contact method in CODE_OF_CONDUCT.md", `9b8e19e` "Fix PSScriptAnalyzer warnings and pre-commit end-of-file issues", `76cfcde` "Finalize template customization", and `6ed94c2` "Fix OWNER/REPO placeholder URL in DESIGN_DECISIONS.md" — merged via PR #6 and PR #7. These are the *template-customization tail* of the same workflow Frank used for the Phase 1 function cleanup, preserved on the public side of the fence.
- **Why it changed / what prompted it** — Hand-applying a multi-hundred-rule PowerShell style guide, one function at a time, to a Phase 1 script is exactly the kind of mechanical-but-judgment-heavy work an LLM-driven audit plus a coding agent can grind through while a human keeps veto power. By generating discrete, scoped GitHub Issues per function and running each through the Copilot Code Reviewer loop, Frank got a bounded, auditable artifact trail — one issue, one PR, one review thread, one merge — instead of a single sprawling cleanup commit. The formal review-loop protocol in `CLAUDE.md`, with its bounded safety limits and scoring rubric, is the process substrate that made the cleanup tractable and repeatable.
- **Quotable moments** —
  > "The authoritative source of truth for all repository rules is **`.github/copilot-instructions.md`** (the repo-wide constitution). All rules defined there apply without exception. **Read that file before making any changes.**" — `CLAUDE.md` line 8

  > "**Maximum rounds:** 8 review iterations per loop invocation. After the eighth round, **PAUSE** regardless of outcome..." — `CLAUDE.md`, Automated Review Loop safety limits

  > "Run `pre-commit run --all-files` before every commit. Include all auto-fixes in the same commit as the related change." — `CLAUDE.md` essential-repo summary; paired with `auto-fix-precommit.yml` as the `copilot/**`-branch safety net, pre-commit is enforced twice.
- **Talk-worthy tags** — `#agent-as-backlog-generator` `#copilot-cleanup-loop` `#parallel-agent-workflow` `#portable-prompt-posture` `#formal-review-loop`



## Phase F — Chicago sync, repo template, and the Codex-authored roadmap


### Chicago whiteboard to repo-from-template

- **Stage purpose** — Move from a single hardened script sitting in isolation to a real, opinionated project: a fresh repo created from Frank's personal template, a backlog Codex could actually build from, and the per-agent + per-language instruction scaffolding needed for the Phase G build-out.

- **What changed**
  - `c2e1325` "Upload initial Watch-Network.ps1" (Frank, 2026-02-20) — the Phase 1 → Phase 2 handoff. The hardened script lands in the newly minted `PSConnMon` repo, created from Frank's personal repo template. The template ships with per-agent instruction files (`CLAUDE.md`, `.github/copilot-instructions.md`, `AGENTS.md` for OpenAI Codex, `GEMINI.md`) and per-language style guides under `.github/instructions/` for docs, PowerShell, and Python.
  - `3f61e11` "Add roadmap doc" (Blakelishly, 2026-03-06) — Blake fed the rough Chicago-whiteboard notes to OpenAI Codex, which synthesized `PSConnMon_Roadmap.md`: ~328 lines, eleven `##` sections (Core Improvements, Input Model Improvements, Logging and Telemetry, Multi-Platform Support, Authentication Testing, Network Quality Features, Extensibility, Visualization & Reporting, Open Architecture Questions, Style and Quality Notes, Long-Term Vision). Status: Active, Last Updated 2026-04-09.
  - `ae7bec1` "Initial plan" (copilot-swe-agent[bot], 2026-03-26), then `49f989c` "fix: demote H1 section headings to H2/H3 in PSConnMon_Roadmap.md to resolve MD025 errors" and `68ebd15` "docs: add standard header block to PSConnMon_Roadmap.md per docs standards" — the GitHub Copilot coding agent cleaning up the markdownlint and docs-header drift that Codex's output had; merged via PR #10.
  - `8868982` "Sync style guide updates" (Frank, 2026-03-26) — a maintenance pass keeping the per-language instruction files current so both Copilot and Codex were working against the same style-guide version when Phase G kicked off.

- **Why it changed / what prompted it** — Frank and Blake met in person at their Chicago office to review the Phase 1 hardened script and decide "what next." They took rough notes on desired improvements, but the hand-written list was too unstructured to hand to an agent. The fix was twofold: (1) stand up the repo from Frank's template so the project inherits opinionated agent and style-guide scaffolding on day one, and (2) let Codex turn the rough notes into a structured backlog an agent could execute against. The roadmap explicitly references `.github/instructions/powershell.instructions.md`, `.github/instructions/python.instructions.md`, and `.github/instructions/docs.instructions.md` in its Style and Quality Notes section — i.e. Codex was instructed to honor those style guides during the v1 build-out that comes in Phase G. The roadmap also foreshadows five "Implemented with v1 decision" callouts (Input Model, Logging/Telemetry, Authentication, Extensibility, Visualization) plus one aggregate "closed for v1 by ADR-0002/ADR-0003" block in Open Architecture Questions — every one of which Phase G's mega-implementation resolves retroactively.

- **Quotable moments**
  - From the roadmap's opening Purpose/Scope block:
    > This document tracks planned improvements, architectural questions, and feature additions for **PSConnMon**.
    >
    > The goal is to improve reliability, expand platform support, and introduce centralized telemetry and visualization.
  - From the Visualization & Reporting section, the key question that ADR-0002 would later settle:
    > Key question:
    >
    > > Is **Azure Storage** the best destination for telemetry?

- **Talk-worthy tags** — `#portable-prompt-posture` `#parallel-agent-workflow` `#agent-as-backlog-generator` `#live-pairing-cadence`


## Phase G — Codex plans and lands roadmap v1 in one commit


### G.1 Blake iterates on Codex's phased plan, then lets it run for ~1 hour

- **Stage purpose:** Set up the "mega-commit" reveal. Before the big diff hits the screen, the audience needs to know the commit did not appear by accident: Blake used Codex's planning skill, iterated on the plan with Codex until he was satisfied, and only then told Codex to execute — with one explicit piece of creative latitude ("take creative liberty with the dashboard"). The actual agent run then took roughly an hour and produced on the order of 5,000 lines of new code.
- **What changed:** Nothing yet lands in the repo during the planning back-and-forth — that is the whole point of this beat. The planning conversation is off-repo (Codex session transcripts, not Git history), so the only thing we can cite is the *next* commit (`7718c30`) as the downstream artifact of that plan. Evidence gap called out on stage: no in-repo artifact captures the phased plan or the iteration passes; the repo only sees the output, not the planning process.
- **Why it changed / what prompted it:** Phase F ended with a roadmap that explicitly asked for a two-tier (monitor + reporting service) architecture, JSON event batches, Azure delivery, and a built-in dashboard. That scope is too large for a single ad-hoc prompt, so Blake routed it through Codex's planning skill, converged the plan through iteration, then handed execution off. The creative-liberty note on the dashboard is the one place Blake deliberately under-specified so the agent could make product calls rather than mechanical ones.
- **Quotable moments:**
  > Blake's directive to Codex: *take creative liberty with the dashboard.*

  > Evidence gap: the planning sessions are not captured in the repo. The only surviving artifact of the plan is the commit it produced.
- **Talk-worthy tags:** `#one-shot-mega-commit` `#adrs-emerged-unprompted` `#backwards-compat-bias`

### G.2 The mega-commit: `7718c30` "Address roadmap items v1"

- **Stage purpose:** This is the slide where the diffstat goes on screen and the audience realizes the entire two-tier architecture landed in a single commit. The contrast between the scope of the change and the length of the commit message is the punchline.
- **What changed:**
  - **SHA / author / date:** `7718c3055609a053266fe785e64a46b5ea06c914`, Blake Cherry <bcherry007@gmail.com>, Thu Apr 9 23:06:10 2026 -0500.
  - **Diffstat:** 56 files changed, 6,855 insertions, 7,079 deletions — **net -224 lines** despite introducing an entire second runtime, because `Watch-Network.ps1` sheds 6,246 lines in the same commit.
  - **PowerShell module (NEW):** `PSConnMon/PSConnMon.psm1` (+2,280) and `PSConnMon/PSConnMon.psd1` (+33, the module manifest).
  - **PowerShell script (GUTTED):** `Watch-Network.ps1` loses 6,246 lines — the monolith is not deleted, it is hollowed out.
  - **Python service (NEW):** eight files, 1,609 lines total, under `src/psconnmon_service/` — `__init__.py` (+5), `__main__.py` (+15), `app.py` (+100), `config.py` (+71), `importer.py` (+293), `models.py` (+183), `storage.py` (+515), `ui.py` (+427).
  - **ADRs (NEW):** `docs/adr/ADR-0001-agent-service-architecture.md` (+44), `docs/adr/ADR-0002-telemetry-and-import-topology.md` (+47), `docs/adr/ADR-0003-extension-trust-boundary.md` (+42) — all three co-land with the code they describe.
  - **Spec (NEW):** `docs/spec/architecture.md` (+83), `docs/spec/requirements.md` (+139).
  - **Runbooks (NEW):** `docs/runbooks/demo.md` (+45), `docs/runbooks/troubleshooting.md` (+40). Note: `docs/runbooks/distributed-deployment.md` does **not** land here — it arrives later in `ef879ed`.
  - **Schemas (NEW):** `schemas/psconnmon-config.schema.json` (+64), `schemas/psconnmon-event.schema.json` (+83).
  - **Samples (NEW):** six files, 406 lines — `azure-branch` and `local-lab` configs in both JSON and YAML, a sample extension probe, and `samples/ingest/sample-batch.json`.
  - **Tests (NEW):** six files, 887 lines — `tests/PowerShell/PSConnMon.Tests.ps1` (+507) plus the pytest suite (`test_app`, `test_importer`, `test_models`, `test_storage` + `conftest.py`).
  - **Terraform (NEW, later removed):** six files under `infra/terraform/azure/` (main/variables/outputs/providers + README + demo.tfvars), 496 lines — Codex committed to cloud infra in v1 and subsequently walked it back.
  - **Container + tooling:** `Dockerfile` (+20), `docker-compose.yml` (+22), `.dockerignore` (+11), plus churn in `.pre-commit-config.yaml` and `pyproject.toml`.
  - **Top-level docs:** 383-line `README.md` rewrite, 142-line roadmap churn.
  - **Template removals (10 files, 739 deleted lines):** `src/copilot_repo_template/`, `templates/powershell/Example.Tests.ps1`, `templates/python/*`, `tests/PowerShell/Placeholder.Tests.ps1`, `tests/__init__.py`, `tests/test_example.py` — the scaffolding gets deleted atomically with the real code landing.
- **Why it changed / what prompted it:** This is the execution phase of the Codex plan from G.1. The roadmap had called out every one of these concerns (module extraction, JSON events, Azure delivery, dashboard, extensibility, multi-platform probes), and Codex's plan bundled them into one atomic change rather than sequencing them. The net-negative delta is a tell that this is a genuine refactor, not additive accretion.
- **Quotable moments:**

  The entire commit message body, verbatim from `git log -1 --format=%B 7718c30`:

  ```
  Address roadmap items v1
  ```

  That is the complete message — no body, no trailer, no bullet list. The ADRs and spec files *are* the narrative; Codex chose to document via artifacts rather than via commit prose.

  The `Decision` and `Consequences` blocks of ADR-0001, landing in this same commit:

  ```
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
  ```
- **Talk-worthy tags:** `#one-shot-mega-commit` `#monolith-to-module` `#script-to-module` `#net-negative-refactor` `#terraform-walk-back`

### G.3 ADRs emerge alongside implementation, not ahead of it

- **Stage purpose:** Close the phase with the observation that pays off on stage: the ADRs were *not* written first. Codex produced the governance artifacts retroactively as part of the same sweep that implemented the decisions they record. This is the "ADRs emerged unprompted" beat.
- **What changed:** Three ADRs land simultaneously in `7718c30`:
  - **ADR-0001 Agent and Service Split** (`docs/adr/ADR-0001-agent-service-architecture.md`, +44): split PSConnMon into a PowerShell monitor (network probes, spooling, Azure config polling) and a Python reporting service (ingestion, query, visualization).
  - **ADR-0002 Telemetry and Import Topology** (`docs/adr/ADR-0002-telemetry-and-import-topology.md`, +47): monitors write canonical JSONL batches locally and optionally upload to Azure Blob; the reporting service pulls from local dir and/or Blob into DuckDB; direct HTTP ingest is demoted to manual-seed/test only.
  - **ADR-0003 Extension Trust Boundary** (`docs/adr/ADR-0003-extension-trust-boundary.md`, +42): v1 extension probes must be trusted local PowerShell files referenced by path only — inline script text in YAML/JSON/Azure-delivered config is rejected, and remote script delivery is rejected.

  All three share identical frontmatter (`Status / Owner / Last Updated / Scope / Related / Date`), all are dated **2026-04-09** (same day as the commit), all are marked **`Status: Accepted`**, all are owned by **"Repository Maintainers"**, and all follow the same Context / Decision / Consequences / Alternatives Considered template. Each ADR also explicitly scopes what it does *not* decide (UI polish, release timing, future analytics backends, future plugin signing) — leaving clean hooks for future ADRs without pre-committing.
- **Why it changed / what prompted it:** Nothing in the roadmap or in Blake's prompt asked for ADRs. Codex introduced them unprompted as part of its plan, then wrote them in the past tense of having already decided — `Status: Accepted` on the same day the code landed. The on-stage framing: these are **retroactive ADRs**, written as implementation artifacts that explain the code that just shipped, rather than pre-decision documents that gate future code. That is a different (and arguably healthier, for an AI-driven workflow) relationship with the ADR format than the textbook version.
- **Quotable moments:**

  ADR-0001 Decision block, verbatim:

  > PSConnMon will use two deployable components:
  >
  > - A **PowerShell monitor** for network-adjacent probes, local spooling, and Azure
  >   config polling.
  > - A **Python reporting service** for ingestion, query, and visualization.

  The three ADRs in one line each:

  > - **ADR-0001:** split into a PowerShell monitor and a Python reporting service.
  > - **ADR-0002:** spool-and-pull via JSONL + Azure Blob + DuckDB; HTTP ingest is demoted.
  > - **ADR-0003:** extensions are trusted local `.ps1` files by path only — no inline script, no remote delivery.

  And the observation to land verbally: *the ADRs were written retroactively as implementation artifacts rather than as pre-decision documents. They describe what Codex had just built, not what Codex was about to build.*
- **Talk-worthy tags:** `#adrs-emerged-unprompted` `#retroactive-adrs` `#backwards-compat-bias` `#one-shot-mega-commit`


## Phase H — Post-roadmap hardening: runbooks, tests, and the nested-traceroute fix


### `ef879ed` "summit fixes" drops the distributed-deployment runbook

- **Stage purpose.** After the roadmap mega-commit and the first CI cleanup merge, Blake asked Codex for an end-to-end deployment runbook he could hand to a branch-office admin. The output — `docs/runbooks/distributed-deployment.md`, roughly **887 lines** — landed under the bland commit message `summit fixes` and is the single densest piece of Linux/AD-interop prose in the repo.
- **What changed.** An eight-step runbook walks from "provision the Azure backend" through "validate the live dashboard," with two entire sub-sections (`### Linux Collector Config` and `#### Credential Handling Model`) devoted to MIT Kerberos on Ubuntu 20.04 talking to a Windows AD KDC. Topics include: package install via `apt-get`, `/etc/krb5.conf` stanza, Windows-side `New-ADUser` + `ktpass` keytab generation, Linux-side `klist -kte` / `kinit -V -k -t` / `smbclient --use-kerberos=required` validation, netplan-based DNS, `_kerberos._tcp` SRV lookup, `timedatectl` clock-skew check, mode-600 keytab files, and a systemd unit for the collector.
- **Why it changed / what prompted it.** Blake needed concrete deployment instructions for the summit demo; Codex produced them at a level of Linux/Kerberos specificity well beyond what a Windows/MS admin would typically know unprompted. The apt-get line alone names four packages a Windows-primary author would not volunteer — `traceroute`, `smbclient`, `dnsutils`, and especially `krb5-user` (the MIT Kerberos client package that ships `kinit`, `klist`, and `kvno`):

  ```bash
  sudo apt-get update
  sudo apt-get install -y traceroute smbclient dnsutils krb5-user
  ```

  The `/etc/krb5.conf` Codex wrote is not a copy-pasted MIT sample — it sets the specific AD-friendly combination you want when the realm is an AD domain and you don't want reverse-DNS to break ticket validation:

  ```ini
  [libdefaults]
      default_realm = CORP.EXAMPLE.COM
      dns_lookup_kdc = true
      dns_lookup_realm = false
      rdns = false

  [realms]
      CORP.EXAMPLE.COM = {
          kdc = dc01.corp.example.com
      }
  ```

  The Windows side is equally specific: `New-ADUser` for the service account, then `Set-ADUser svc-psconnmon -Replace @{'msDS-SupportedEncryptionTypes'=24}` to force AES128+AES256, then `ktpass ... /crypto AES256-SHA1 /ptype KRB5_NT_PRINCIPAL /pass *` to mint the keytab. The `msDS-SupportedEncryptionTypes=24` flag is the one most admins forget — Codex included it. The Linux validation chain then runs `klist -kte` on the keytab, `kinit -V -k -t` under a throwaway `KRB5CCNAME`, `klist` again to confirm, and proves the ticket works with `smbclient //dc01.corp.example.com/SYSVOL --use-kerberos=required`, all under `sudo -u blake` so cache-path ownership is exercised the same way the systemd unit will exercise it.
- **Quotable moments.** "`dns_lookup_kdc = true`, `dns_lookup_realm = false`, `rdns = false`" is Kerberos-interop folklore, not generic Linux docs. "The principal string in the keytab MUST exactly match the principal configured in the Linux secret JSON." The `apt-get install -y traceroute smbclient dnsutils krb5-user` one-liner as a single-slide reveal of how much Linux-side context Codex produced unbidden. Evidence gap worth flagging honestly on stage: no explicit `setspn`, SELinux/AppArmor, `ufw`, `chrony`/`ntp`, or UID/GID numerics — clock sync gets a `timedatectl status` and nothing more.
- **Talk-worthy tags.** `#codex-knew-linux`, `#parallel-agent-workflow`, `#live-pairing-cadence`.

### The nested-traceroute bug and its fix in `521b367` "updates"

- **Stage purpose.** This is the phase's cleanest "the tests passed, the design was still wrong" moment. Real deployment feedback — not a failing unit test — exposed a data-model mistake Codex had locked into the schema during the roadmap mega-commit, and Blake's fix is a data-model promotion rather than a probe-logic change.
- **What changed.** Commit `521b367` by Blake Cherry, **Mon Apr 13 19:53:26 2026 -0700**, **22 files changed, 1,134 insertions / 209 deletions**, with the entire commit message literally:

  ```
  updates
  ```

  The v1 model assumed every `target` was an internal host (with `id`, `fqdn`, `address`, `shares`, etc.) and carried an `externalTraceTarget` property nested underneath it to tell the traceroute probe where to actually go. The schema even made `externalTraceTarget` a **required** property on every target. Operationally that meant internet path monitoring was a passenger on an internal-target probe — if the internal host was unreachable, decommissioned, or simply absent, you lost the ability to probe the internet alongside it, even though those probes have nothing to do with that host. The fix promotes internet probes to a first-class `internetTargets` array (schema-required at the top level), relaxes `targets` so it no longer requires `minItems: 1` or a nested `externalTraceTarget`, and auto-migrates legacy configs at load time by synthesizing internet-target entries tagged `tags: ['external', 'legacy-migrated']`. A new `Get-PSConnMonInternetProbeAddress` helper gives any legacy config a fallback address-resolution path so the module keeps limping along while the migration runs.
- **Why it changed / what prompted it.** Nothing in the roadmap or spec explicitly decoupled "traceroute target" from "internal-host target." Codex logically concluded that traceroute and internet-quality were *tests*, tests belonged to *targets*, and therefore the trace destination belonged as a nested property on a target. The Pester and pytest suites were happy with that model. The bug only surfaced when Blake tried to actually deploy PSConnMon to branch sites and realized he wanted to monitor internet paths independently of any internal host. The auto-migration block that emerged is the punchy bit — it stamps each rewritten entry with a literal forensic breadcrumb:

  ```diff
  +            $legacyInternetTargets.Add(@{
  +                id = $candidateInternetId
  +                name = ('{0} Internet' -f [string]$targetValue.fqdn)
  +                address = $internetAddress
  +                tests = if ($legacyInternetTests.Count -gt 0) { $legacyInternetTests } else { @('internetQuality', 'traceroute') }
  +                roles = @('internet')
  +                tags = @('external', 'legacy-migrated')
  +                targetKind = 'external'
  +            }) | Out-Null
  ```

  The `tags = @('external', 'legacy-migrated')` line is the forensic receipt: every time an operator sees `legacy-migrated` on an internet target, they are looking at evidence of a requirements-spec miss that an AI agent locked into the schema.
- **Quotable moments.** A 22-file, 1,134-line rearchitecture across PowerShell module, Python service, JSON schema, samples, docs, and tests — shipped under the one-word commit message `updates`. The `legacy-migrated` tag itself, which will outlive the talk as a live artifact in operator-facing data. The backwards-compat bias: this tool is explicitly pre-production, a clean break would have been defensible, and Blake still shipped a migration path instead of breaking the schema — a continuation of Codex's own bias, arguably stronger than the situation warranted.
- **Talk-worthy tags.** `#requirements-gap`, `#legacy-migrated-breadcrumb`, `#backwards-compat-bias`, `#one-shot-mega-commit`.

### The tracert and dashboard iteration arcs

- **Stage purpose.** Step back from the individual commits and look at the *cadence*. Phase G was a single mega-commit (`7718c30` "Address roadmap items v1") where Codex ran the whole roadmap to completion in one shot. Phase H is the opposite shape: dozens of terse, lowercase, same-subject-line commits authored by Blake locally, minutes apart, pairing live with Codex while the summit demo and the runbook were both driving feedback.
- **What changed.** Three tightly-coupled arcs, all on 2026-04-13, all authored by Blake Cherry (or `blakelishly`), visible in the git log as a chain of two- or three-word messages:
  - **Tracert iteration arc** (before the big fix): `edeb30c` "tracert fixes" → `388eae9` "change tracert reporting" → `1f0bfd1` "enhance tracert timeout" — three separate probe-level passes, each a small tweak that didn't solve the real problem, culminating in the `521b367` data-model rewrite above.
  - **Dashboard polish arc** (wrapped around the tracert fix): `eca787c` "resolve UI errors" pre-dates the summit work; then after `521b367` lands the dashboard work resumes as `7121555` "dashboard fix" → `f37e3b6` "fix dash" → `9722f72` "dashboard fixes" → `01030e8` "more dashboard fixes" → `fd912ce` "dashboard fixes". Six consecutive dashboard commits, two of which share the exact same subject line, is the clearest single log-level signature of live pairing cadence in the repo.
  - **SUMMIT_FIXES cluster** (demo-output churn): `ef879ed` "summit fixes" (the runbook), `38ff47f` "demo edits and sample outputs", `680fbd8` / `b8fa01e` "new test output(s)", `895bcc1` "update tests" — Codex running tests locally, Blake iterating on the resulting sample outputs, both of them converging on something demo-ready.
- **Why it changed / what prompted it.** The shape of this phase is driven by two external pressures that the roadmap mega-commit did not face: an imminent summit demo and the first real attempt at a distributed deployment. Both generate feedback at a scale of minutes, not days, and both want many small committed checkpoints rather than one reviewable change. Blake's message style — `"fixes"`, `"updates"`, `"fix dash"`, reusing the same subject line across commits — is a direct signal of workflow mode. These are not review artifacts; they are live-pairing checkpoints.
- **Quotable moments.** Six dashboard commits in a row, two with identical subject lines. A 1,134-line rearchitecture titled `updates`. The contrast with Phase G's single `7718c30` "Address roadmap items v1" mega-commit: same project, same agent, but a completely different cadence once a human is in the loop with concrete feedback. The Copilot PR-cycle commits over the same period (authored by `copilot-swe-agent[bot]`) are by contrast verbose and scope-prefixed — the log itself is a legend for which workflow mode produced which change.
- **Talk-worthy tags.** `#live-pairing-cadence`, `#parallel-agent-workflow`, `#one-shot-mega-commit`.


## Phase I — CI fixes, Terraform walk-back, and the formal Claude review loop


### Phase I.a — CI shakedown via Copilot PRs #13 and #16 + Frank's Terraform walk-back

After the mega-commit dust settled, the repo quickly revealed three classes of bit-rot that Blake's live pairing with Codex hadn't caught: PowerShell `$event` collisions, Python test assertions drifting against real behavior, and a platform-unsafe `dig` test on Windows runners. Frank's response was not to ask Codex or Claude to fix them — it was to dispatch two targeted issues to GitHub Copilot's coding agent and take the fixes through formal PRs.

- **Stage purpose.** Convert red CI into green CI without re-entering live-pairing mode; simultaneously prune Phase G's unprompted Terraform bet back to the project's actual scope.
- **What changed.**
  - **PR #13** (merged `462612c`): Copilot coding agent authored `af8235b` *"Fix PowerShell CI errors: rename $event to $connMonEvent, skip YAML test when unsupported"* and `115112d` *"Clarify YAML skip condition using De Morgan's law for readability"* — both as `copilot-swe-agent[bot]`.
  - **PR #16** (merged `e816338`): Copilot coding agent authored `70204ba` *"Fix CI failures: rename plural noun, fix Python test assertions, skip dig test on Windows"*.
  - **Frank's cleanup burst, 2026-04-13/14, authored directly** (not through Copilot): `74772a2` *"Remove Terraform and placeholder content"*, `84768b1` *"Remove instructions to customize for your project"*, `90e4215` *"Update agent instructions to latest versions from template repo"*, `37b3ae6` *"Update PowerShell instructions to version 2.7.20260414.0"*.
  - **Blake-local CI micro-pass.** `87d8d57` *"fix CI issues"* sits inside the dashboard-polish arc — the terse-lowercase signature of a live checkpoint, not a review artifact.
- **Why it changed / what prompted it.** The PowerShell and Python failures were mechanical regressions from the mega-commit; the right tool was a scoped Copilot issue with a tight blast radius. The Terraform removal is the more interesting move: `infra/terraform/azure/*` had landed unprompted inside `7718c30`, and Frank explicitly walked it back rather than preserving it "just in case." This is the rare case where backwards-compat bias is deliberately violated — speculative infrastructure generated by Codex is treated as cost, not asset, and deleted.
- **Quotable moments.**
  - The workflow-mode signal is in the commit messages themselves: the Copilot bot writes *"Fix PowerShell CI errors: rename $event to $connMonEvent, skip YAML test when unsupported"* — conventional, imperative, scoped. Blake's contemporaneous commits read *"fixes"*, *"fix dash"*, *"dashboard fixes"* (three times in a row). Same repo, same week, two completely different operating modes.
  - Frank's four cleanup commits use uniform *"Update X"* / *"Remove Y"* phrasing in a tight sequence — the human-in-the-loop pruning voice, distinct from both Blake's live-pairing terseness and the Copilot bot's PR-formal tone.
- **Talk-worthy tags.** `#copilot-cleanup-loop`, `#terraform-walk-back`, `#backwards-compat-bias` (inverted — we intentionally do *not* preserve the Terraform directory).

### Phase I.b — PR #14 fires the formal CLAUDE.md review loop

PR #14 is the first and, so far, only time this repo exercises the review protocol codified in `CLAUDE.md`. Four commits, all authored by "Claude," all on 2026-04-14, land in a single arc: `a26f60f` *"Address Copilot review feedback on PR #14"*, `d519fd3` *"Address Copilot round 2 review feedback on PR #14"*, `2e443c1` *"Apply black reformat to models.py field_validator shim"*, `f19a0ac` *"Address Copilot round 3 review feedback on PR #14"*. The message scheme itself is evidence of discipline — three numbered rounds plus one formatter cleanup, documented in-subject.

- **Stage purpose.** Execute the CLAUDE.md-codified review discipline as a bounded loop, not as ad-hoc back-and-forth. Demonstrate that the nine-step rubric + active-polling loop can drive a PR to green through multiple review passes without human arbitration per-comment.
- **What changed.** Four Claude-authored commits on PR #14. Each of the three "rounds" commits corresponds to a full pass through the nine-step "Handling Code Review Comments" protocol on every open Copilot comment from that round's review. The interstitial `2e443c1` is a mechanical `black` reformat on `models.py`'s `field_validator` shim — exactly the kind of formatter-only touch-up that the protocol tolerates inline rather than splitting into a separate PR.
- **Why it changed / what prompted it.** The protocol itself defines the why. From the `CLAUDE.md` "Automated Review Loop," the safety-limits block quoted verbatim:

  > - **Maximum rounds:** 8 review iterations per loop invocation. After the eighth round, **PAUSE** regardless of outcome and post:
  >   `Review loop paused: reached maximum of 8 review rounds. Post "@claude resume review loop" to continue.`
  > - **Wall-clock timeout:** 6 hours from loop start. If the timeout is reached, **PAUSE** and post:
  >   `Review loop paused: 6-hour timeout reached. Post "@claude resume review loop" to continue.`
  > - **Duplicate detection:** Track comment IDs that have already been processed. Skip any comment whose ID was addressed in a prior round to avoid re-processing.
  > - **Active polling required:** Every review-wait cycle **MUST** be driven by the explicit timed poll loop described in step 2. Passive waiting for webhook delivery alone is **not** permitted — the poll loop ensures that pause and timeout behavior is reached deterministically even if webhook delivery does not occur.

  The three-rounds-plus-formatter pattern on PR #14 is a live worked example: one `request_copilot_review` per round, 60-second-minimum polling until the bot's review summary lands, nine-step rubric per comment (options table → 1-5 scoring table → select-or-escalate → implement → style-guide impact check → resolve/leave-open), then loop back to step 1. Three rounds is well inside the 8-round ceiling; the loop exited naturally on a clean pass, not on a safety limit.
- **Quotable moments.**
  - **Separation of powers.** Step 8 of the "Handling Code Review Comments" protocol forbids the reviewing agent from editing `.github/instructions/` directly — style-guide changes must be posted as a code-fenced prompt aimed at GitHub Copilot's coding agent. The review agent reviews; a different agent edits the rules. Two agents, two mandates, one repo.
  - **Active polling as a first-class requirement.** *"Passive waiting for webhook delivery alone is not permitted."* The loop is engineered so that PAUSE and timeout semantics remain deterministic even when webhooks never arrive.
  - **Round-numbered commit messages.** *"Address Copilot round 2 review feedback on PR #14"* is the most process-disciplined commit message in the log — a structural contrast to Blake's three-in-a-row *"dashboard fixes"*.
- **Talk-worthy tags.** `#formal-review-loop`, `#parallel-agent-workflow`, `#portable-prompt-posture`.

### Phase I.c — What all of this together shows

Phase I is the moment the repo's agent posture snaps into focus. CI regressions left behind by Phase G's mega-commit get repaired through *dispatched Copilot issues* (PRs #13 and #16) rather than in-place live pairing — scoped, conventional-message, PR-reviewable work. In parallel, Frank's cleanup burst performs a human-in-the-loop pruning pass, deleting Terraform and placeholder scaffolding that Codex had speculatively generated — a direct walk-back of Phase G over-reach and a conscious choice to break backwards compatibility on infrastructure scope. And PR #14 fires the formal CLAUDE.md review loop for the first time, turning the review discipline that Phase E exercised informally through the Copilot Code Reviewer into a codified, safety-limited, actively-polled protocol with round-numbered commits as its audit trail. Three agents, three operating modes, one constitution.

- **Talk-worthy tags.** `#formal-review-loop`, `#copilot-cleanup-loop`, `#terraform-walk-back`, `#parallel-agent-workflow`.


## Arc summary

Phase 2 is the story of four distinct agentic workflow patterns stacking on top of one another in the same repo. It opens in **Phase E** with the *issue-per-function Copilot cleanup loop*: an LLM-based audit of Frank's PowerShell style guide produces a backlog of paired assess/remediation GitHub Issues — one pair per function — which Frank dispatches to GitHub Copilot's coding agent roughly four at a time, reviews with Copilot Code Reviewer, and either re-dispatches or hand-fixes based on adjudication. The backlog generator itself lives in a private repo, but the footprint is visible here in the per-agent instruction files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`), the five `.github/workflows/` YAMLs — especially `auto-fix-precommit.yml` as the `copilot/**`-branch safety net — and the tail end of the pre-mega timeline (PRs #6, #7, #10). The pattern then shifts in **Phases F and G** to a *roadmap-driven one-shot mega-commit*: Blake brings rough Chicago-sync notes to OpenAI Codex, Codex synthesizes `PSConnMon_Roadmap.md` (`3f61e11`), Blake iterates on the phased plan, and roughly an hour of Codex runtime later lands `7718c30` "Address roadmap items v1" — 56 files, 6,855 insertions, 7,079 deletions, one-line commit message, with the PowerShell module, the Python service, three ADRs, spec, runbooks, schemas, samples, Pester and pytest suites, Docker, and Terraform all co-landing atomically. The ADRs are written in past tense the same day as the commit; they are implementation artifacts retroactively framed as decisions, not pre-decision governance.

**Phase H** drops the cadence by two orders of magnitude into *live pair-programming with Codex*: once deployment feedback surfaces the nested-traceroute requirements miss, the missing Linux/Kerberos specifics, and the dashboard UX gaps, Blake's commit messages collapse to terse lowercase checkpoints — "updates", "tracert fixes", "dashboard fix", three successive "dashboard fixes" in a row — because each commit is a minutes-scale save point in a live session, not a PR-grade artifact. **Phase I** then formalizes the cleanup discipline through PR #14, where the `CLAUDE.md` 9-step "Handling Code Review Comments" protocol and the Automated Review Loop (with its 8-round maximum, 6-hour wall clock, and 10-poll timeout) are exercised across three rounds of Copilot review feedback by Claude-authored commits. Contrast this with Phase 1, which was a chat-driven parallel-experts loop — Frank typing into multiple LLMs and synthesizing results by hand; Phase 2 moves the human off the keyboard for *generation* and onto the keyboard for *dispatch, adjudication, and integration*. Agents write the code; humans route, review, and reconcile.

The honest asymmetry worth naming on stage is that the Codex mega-commit feels like a leap but is not a solo act — it is bracketed on both sides by disciplined human-in-the-loop steps. A codified planning pass precedes it (the Codex-authored roadmap in Phase G, iterated with Blake before any implementation begins), and a visible hardening-and-walk-back arc follows it: the tracert fixes, the dashboard polish sequence, the CI fix waves, and eventually Frank's `74772a2` "Remove Terraform and placeholder content" — a deliberate walk-back of infrastructure that Codex over-committed to in v1. Every Phase 2 pattern has a concrete artifact in this repo you can point at in order: the per-agent instruction files and the `auto-fix-precommit.yml` workflow for the issue-per-function loop, `PSConnMon_Roadmap.md` and the one-line `7718c30` mega-commit for the roadmap-driven pattern, the `legacy-migrated` tag and the terse lowercase commit run for live Codex pairing, and the `CLAUDE.md` review protocol plus the Terraform-removal commit for the codified cleanup. The talk can walk those artifacts in order and let the commit log narrate itself.
