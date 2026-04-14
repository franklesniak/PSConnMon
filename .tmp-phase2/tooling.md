# Agent tooling extractor output

## Canonical instructions

**Source of truth.** CLAUDE.md, AGENTS.md, and GEMINI.md all declare the same constitution. Quoted from CLAUDE.md (line 8):

> "The authoritative source of truth for all repository rules is **`.github/copilot-instructions.md`** (the repo-wide constitution). All rules defined there apply without exception. **Read that file before making any changes.**"

Inside `.github/copilot-instructions.md` itself, the README is called out as the functional contract (line 8):

> "The `README.md` file describes the project's features, parameters, and behavior. When in doubt, the README is the authoritative reference for intended functionality."

**Per-agent instruction files present in the repo:**

| Agent family | Instruction file | Notes |
|---|---|---|
| Claude Code | `CLAUDE.md` | Version 1.2.20260414.0. Minimal inline summary, then the full "Handling Code Review Comments" and "Automated Review Loop" protocols. Defers to `.github/copilot-instructions.md`. |
| GitHub Copilot | `.github/copilot-instructions.md` | Version 1.1.20260112.0. The "repo-wide constitution"; authoritative for safety/security, pre-commit discipline, and the Copilot Coding Agent workflow. |
| OpenAI Codex / Codex CLI | `AGENTS.md` | Version 1.1.20260412.1. Near-identical summary shape to CLAUDE.md/GEMINI.md; defers to the copilot-instructions constitution. |
| Google Gemini | `GEMINI.md` | Version 1.1.20260412.1. Same structure and content as `AGENTS.md`, aimed at Gemini Code Assist; also defers to the copilot-instructions constitution. |

## Per-language instruction files (.github/instructions/)

| File | Scope / Intent |
|---|---|
| `.github/instructions/docs.instructions.md` | `applyTo: "**/*.md"` — "Documentation standards: contract-first, traceable, drift-resistant Markdown." Governs all repo Markdown (README, `docs/**`, ADRs, runbooks, release notes); treats documentation as a first-class engineering artifact (contract, design record, maintenance tool) and mandates normative RFC 2119 language. |
| `.github/instructions/powershell.instructions.md` | `applyTo: "**/*.ps1"` — "PowerShell coding standards." Version 2.7.20260414.0. Covers style, formatting, naming, error handling, documentation, and compatibility for both legacy PS v1.0 and modern v2.0+ code; tags every rule `[All]`, `[Modern]`, or `[v1.0]`. |
| `.github/instructions/python.instructions.md` | `applyTo: "**/*.py"` — "Python coding standards: portability-first by default, modern-advanced when the stack requires it." Version 1.1.20260113.0. Default posture is stdlib-first and portability-first; shifts to modern-advanced (typing, async, Pydantic/FastAPI) only when the stack demands it. |

## Workflow set

Files discovered under `.github/workflows/` (filename-only inference, per instructions — workflow bodies were not opened):

- `check-placeholders.yml` — Likely scans source/docs for unreplaced placeholder tokens (e.g., `TODO`, templated `{{ }}` markers) before merge.
- `auto-fix-precommit.yml` — Referenced in `.github/copilot-instructions.md` as a safety net that runs pre-commit hooks and auto-commits fixes on `copilot/**` branches when the Copilot Coding Agent pushes code that fails checks.
- `python-ci.yml` — Python CI: presumably runs `pytest tests/ -v --cov --cov-report=term-missing` (the Python validation command named in the constitution) plus lint/format gates.
- `powershell-ci.yml` — PowerShell CI: presumably runs `Invoke-Pester -Path tests/ -Output Detailed` (the PS validation command named in the constitution) plus PSScriptAnalyzer-style checks.
- `markdownlint.yml` — Markdown CI: presumably runs `npm run lint:md` (the Markdown validation command named in the constitution).

## "Handling Code Review Comments" protocol (CLAUDE.md)

Applies to every review comment from Copilot, humans, or any reviewer on a PR. Each comment is processed independently through nine steps:

- **Step 1 — Signal processing.** Add an `:eyes:` reaction when starting, remove it when done. Quoted: *"The GitHub MCP server does not currently expose `add_reaction` or `remove_reaction` endpoints for review comments. Skip this step until the tooling is available."*
- **Step 2 — Validate the concern.** If the feedback isn't valid, reply explaining why, skip steps 3-8, jump to step 9.
- **Step 3 — List options.** Enumerate every reasonable fix.
- **Step 4 — Build a rubric.** Quoted: *"Define 4-6 scoring criteria relevant to the concern (e.g., style guide compliance, performance, code simplicity, PII safety, PS 5.1 compatibility). Score each criterion on a 1-5 scale."*
- **Step 5 — Score, select, or escalate.** Apply the rubric in a Markdown table; pick the highest total. Quoted escalation trigger: *"If the rubric cannot produce a clear winner — because the decision depends on owner preferences, project-level policy, or the top options are too close to differentiate objectively — escalate to the PR owner instead of selecting an option."* The standalone PR comment must end with the instruction *"Reply to this comment starting with `@claude` followed by your chosen option or direction."* Processing of that comment PAUSES until the owner responds; other independent comments continue.
- **Step 6 — Post the evaluation.** Reply with options table, scoring table, selection, and either a follow-up note or the implementing commit SHA.
- **Step 7 — Implement the fix.** Apply, commit, push.
- **Step 8 — Evaluate style-guide impact.** Read the full applicable `.github/instructions/` file(s) first, then decide whether a style-guide update is warranted. Quoted: *"If an update is warranted, write a prompt in a Markdown code fence (suitable for sending to GitHub Copilot's coding agent) that describes the style guide change. Post the prompt as a reply in the same review comment thread. Do **not** modify the style guide directly."*
- **Step 9 — Resolve or leave open.** Quoted: *"If **no** style guide update was recommended in step 8, resolve the review comment thread using the `resolve_review_thread` tool (or equivalent). If a style guide update **was** recommended, leave the thread **open** so the owner can see and act on the prompt before it is dismissed."* A known tooling limitation is noted: `resolve_review_thread` needs a `PRRT_...` GraphQL node ID that current `get_review_comments` responses omit.

## "Automated Review Loop" protocol (CLAUDE.md)

Triggered on PR creation or by a PR comment containing `@claude start review loop`. The cycle:

- **Step 1 — Request a Copilot review.** First snapshot the `submitted_at` of the most recent review by `copilot-pull-request-reviewer[bot]` as a baseline, then call `request_copilot_review`.
- **Step 2 — Active polling for the new review.** Minimum 60 seconds between every `get_reviews` call (including the gap before the first poll). Detection = any bot review with `submitted_at` strictly newer than the baseline; the "Pull request overview" summary comment ("generated N comments") is the authoritative signal. Webhook-only waiting is explicitly disallowed. Recommends a visible per-poll progress indicator. If no new review arrives after **10 consecutive polls (~10 min)**, PAUSE and post: `Review loop paused: Copilot review did not arrive after 10 poll attempts (~10 min). Post "@claude resume review loop" to continue.`
- **Step 3 — Check review coverage.** If Copilot reviewed fewer files than were changed, post a PR comment flagging the partial coverage (example text: `Note: Copilot reviewed only 7 out of 9 changed files in round N. ...`). Continue the loop regardless.
- **Step 4 — Check for comments.** Zero actionable comments ⇒ PAUSE with `Review loop paused: Copilot review returned no comments. Post "@claude resume review loop" to continue.`
- **Step 5 — Process each comment** via the 9-step "Handling Code Review Comments" protocol, skipping/working around tooling limits but still completing the step-9 intent manually when needed.
- **Step 6 — Check for style-guide recommendations.** If any comment produced a step-8 style-guide prompt, PAUSE with `Review loop paused: style guide update(s) recommended — see review thread(s) above. Apply the style guide changes, then post "@claude resume review loop" to continue.`
- **Step 7 — Re-request review.** Otherwise loop back to step 1, even if no code changed, so Copilot gets a fresh pass.
- **Resume semantics.** `@claude resume review loop` restarts from step 1 and resets both the round counter and the wall-clock timeout.

Safety-limits block, quoted verbatim:

> - **Maximum rounds:** 8 review iterations per loop invocation. After the eighth round, **PAUSE** regardless of outcome and post:
>   `Review loop paused: reached maximum of 8 review rounds. Post "@claude resume review loop" to continue.`
> - **Wall-clock timeout:** 6 hours from loop start. If the timeout is reached, **PAUSE** and post:
>   `Review loop paused: 6-hour timeout reached. Post "@claude resume review loop" to continue.`
> - **Duplicate detection:** Track comment IDs that have already been processed. Skip any comment whose ID was addressed in a prior round to avoid re-processing.
> - **Active polling required:** Every review-wait cycle **MUST** be driven by the explicit timed poll loop described in step 2. Passive waiting for webhook delivery alone is **not** permitted — the poll loop ensures that pause and timeout behavior is reached deterministically even if webhook delivery does not occur.

## What is NOT in this repo

- **The private-repo, function-by-function style-guide audit workflow.** The orchestrator describes a GitHub Actions workflow that ingests a function-by-function style-guide audit and emits a pair of GitHub Issues per function (style-guide assessment + remediation tasks). No such workflow appears in `.github/workflows/` here — the five YAML files present are `check-placeholders.yml`, `auto-fix-precommit.yml`, `python-ci.yml`, `powershell-ci.yml`, and `markdownlint.yml`. The backlog-generation pipeline lives in a private repo, not in this public one. Evidence gap: confirmed by filename enumeration only; workflow bodies were not opened per instructions.
- **No `.github/instructions/` file for JavaScript/TypeScript, YAML, or shell.** Only docs/powershell/python instruction files are shipped, so Markdown/PS/Python are the only languages with formal style guides here.
- **No agent-addressed `.github/chatmodes/`, `.github/prompts/`, or MCP-server config files** visible at the expected paths — the repo's agent posture is purely instruction-file driven, not prompt- or tool-pack driven.
- **No "handle `@claude` mention" dispatcher workflow.** The CLAUDE.md protocols rely on `@claude start review loop` / `@claude resume review loop` PR comments, but no GitHub Action in this repo wires those phrases to an agent runner — the listener presumably lives outside this repository (likely the Anthropic-hosted Claude GitHub App). Evidence gap: inferred from workflow filenames; not verified by opening the files.

## Talk-worthy observations

- **One repo, four agent families, one constitution.** CLAUDE.md, AGENTS.md (Codex), GEMINI.md, and `.github/copilot-instructions.md` coexist, and the first three each explicitly declare the Copilot file the "source of truth." This is a deliberate "portable prompt" posture — the same repo tells every major coding agent to obey the same rules rather than forking guidance per vendor.
- **The Claude file carries the heavyweight process, not the rules.** CLAUDE.md's distinctive content isn't safety rules (those live in the constitution) — it's the formal nine-step code-review rubric and the bounded, actively polled review loop with 8-round / 6-hour / 10-poll safety limits. Claude is positioned as the review-loop driver; other agents get the summary.
- **Style-guide changes go through a prompt, not a direct edit.** Step 8 forbids agents from editing `.github/instructions/` directly; they must instead post a code-fenced prompt aimed at GitHub Copilot's coding agent. This is an intentional separation of powers between the review agent and the style-guide editor agent.
- **Pre-commit is enforced twice.** The constitution mandates local `pre-commit run --all-files`; `auto-fix-precommit.yml` is a CI safety net specifically for `copilot/**` branches where the Copilot Coding Agent pushes dirty code. The private backlog-generation workflow that turns a style-guide audit into per-function GitHub Issues is referenced externally but is not present in this public repo.
- **Active polling is a first-class requirement.** The loop explicitly bans webhook-only waiting and requires a 60-second-minimum timed poll so that PAUSE and timeout semantics remain deterministic — a subtle but important design decision for reliability when running inside an agent harness.
