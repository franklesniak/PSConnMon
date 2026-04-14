# Nested-traceroute fix anatomy (521b367)

## Commit header

- **SHA:** `521b367dba993c07417af485e773da1b77945b25`
- **Author:** Blake Cherry <bcherry007@gmail.com>
- **Date:** Mon Apr 13 19:53:26 2026 -0700
- **Scope:** 22 files changed, **1134 insertions(+), 209 deletions(-)**

Top-touched files (verified from `git show --stat`):

| File | Lines |
|------|-------|
| `PSConnMon/PSConnMon.psm1` | +225 |
| `src/psconnmon_service/ui.py` | +272 |
| `src/psconnmon_service/storage.py` | +263 |
| `tests/PowerShell/PSConnMon.Tests.ps1` | +111 |
| `tests/python/test_storage.py` | +97 |
| `docs/runbooks/distributed-deployment.md` | ~57 |
| `schemas/psconnmon-config.schema.json` | +42 |
| `src/psconnmon_service/models.py` | +38 |
| `README.md` | +37 |
| `samples/config/azure-branch.psconnmon.json` | +30 |
| `docs/spec/architecture.md` | +18 |
| `Watch-Network.ps1` | +17 |
| `samples/config/summit/ubuntu-branch-01.psconnmon.yaml` | +17 |
| `samples/config/summit/win-branch-01.psconnmon.yaml` | +17 |
| `samples/config/azure-branch.psconnmon.yaml` | +15 |
| `samples/config/local-lab.psconnmon.json` | +14 |
| `docs/spec/requirements.md` | +12 |

**Full commit message body** (from `git log -1 --format=%B`):

```
updates
```

That is the entire commit message. A mega-commit that rearchitects the target data model and migrates sample configs, tests, runbooks, schema, Python service, and PowerShell module — shipped under the single word `updates`.

## The underlying bug (1-paragraph narrative)

In the pre-`521b367` data model, traceroute and other internet-quality probes were not first-class targets. Instead, every "target" was assumed to be an **internal** host (with `id`, `fqdn`, `address`, `shares`, etc.), and an optional `externalTraceTarget` **property nested underneath** that internal target carried the address the traceroute probe should actually hit (e.g., `8.8.8.8`). The schema even made `externalTraceTarget` a `required` property on every target. Operationally that meant PSConnMon could not model "trace the path to the internet" as an independent concern: to probe internet connectivity you had to pick some internal target, attach `internetQuality` / `traceroute` to its `tests` list, and then override the trace destination via the nested `externalTraceTarget` field. If the internal target was unreachable, unhealthy, decommissioned, or simply absent, you lost the ability to run internet path diagnostics alongside it — even though those probes have nothing to do with that internal host. Traceroute was effectively a passenger on an internal-target probe rather than its own monitored entity.

## PSConnMon.psm1 diff highlights

The psm1 diff adds (1) an `InternetTargets` parameter/property, (2) a new `Get-PSConnMonInternetProbeAddress` helper that prefers the new external address but falls back to legacy `externalTraceTarget`, and (3) an auto-migration block inside `Test-PSConnMonConfig` that promotes legacy nested targets into first-class `internetTargets` tagged `legacy-migrated`.

**New `InternetTargets` parameter on `ConvertTo-PSConnMonConfig`:**

```diff
@@ -315,6 +327,7 @@ function ConvertTo-PSConnMonConfig {
     [OutputType([hashtable])]
     param(
         [Parameter(Mandatory = $true)][object[]]$Targets,
+        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$InternetTargets = @(),
         [Parameter(Mandatory = $false)][AllowNull()][object]$Agent = $null,
```

```diff
@@ -339,6 +357,7 @@ function ConvertTo-PSConnMonConfig {
         tests = if ($null -eq $Tests) { @{} } else { ConvertTo-PSConnMonHashtable -InputObject $Tests }
         auth = if ($null -eq $Auth) { @{} } else { ConvertTo-PSConnMonHashtable -InputObject $Auth }
         targets = $targetValues.ToArray()
+        internetTargets = $internetTargetValues.ToArray()
         extensions = $extensionValues.ToArray()
```

**"At least one target" guard relaxed to accept either list:**

```diff
-    if ($normalizedConfig.targets.Count -lt 1) {
-        throw 'At least one target is required.'
+    if (($normalizedConfig.targets.Count + $normalizedConfig.internetTargets.Count) -lt 1) {
+        throw 'At least one target or internetTarget is required.'
     }
```

**The auto-migration block — promotes legacy nested traceroute settings into a new first-class `internetTargets` entry tagged `legacy-migrated`:**

```diff
+        $targetValue.targetKind = 'internal'
+
         if (-not $targetValue.ContainsKey('externalTraceTarget')) {
             $targetValue.externalTraceTarget = $targetValue.address
         }
 
+        $legacyInternetTests = @($targetValue.tests | Where-Object { $_ -in @('internetQuality', 'traceroute') })
+        $legacyTraceTarget = [string]$targetValue.externalTraceTarget
+        if (($legacyInternetTests.Count -gt 0) -or ((-not [string]::IsNullOrWhiteSpace($legacyTraceTarget)) -and ($legacyTraceTarget -ne [string]$targetValue.address))) {
+            $candidateInternetId = '{0}-internet' -f $targetValue.id
+            $counterValue = 1
+            while ($targetIds.Contains($candidateInternetId) -or ($legacyInternetTargets | Where-Object { $_.id -eq $candidateInternetId })) {
+                $counterValue++
+                $candidateInternetId = '{0}-internet-{1}' -f $targetValue.id, $counterValue
+            }
+
+            $internetAddress = if ([string]::IsNullOrWhiteSpace($legacyTraceTarget)) {
+                [string]$targetValue.address
+            } else {
+                $legacyTraceTarget
+            }
+
+            $legacyInternetTargets.Add(@{
+                id = $candidateInternetId
+                name = ('{0} Internet' -f [string]$targetValue.fqdn)
+                address = $internetAddress
+                tests = if ($legacyInternetTests.Count -gt 0) { $legacyInternetTests } else { @('internetQuality', 'traceroute') }
+                roles = @('internet')
+                tags = @('external', 'legacy-migrated')
+                targetKind = 'external'
+            }) | Out-Null
+
+            $targetValue.tests = @($targetValue.tests | Where-Object { $_ -notin @('internetQuality', 'traceroute') })
+        }
```

**New helper that resolves the address for internet-facing probes — the seam that lets the module keep limping along when a legacy config arrives:**

```diff
+function Get-PSConnMonInternetProbeAddress {
+    ...
+    if (
+        $Target.ContainsKey('targetKind') -and
+        ([string]$Target.targetKind -eq 'external')
+    ) {
+        return [string]$Target.address
+    }
+
+    if (
+        $Target.ContainsKey('externalTraceTarget') -and
+        (-not [string]::IsNullOrWhiteSpace([string]$Target.externalTraceTarget))
+    ) {
+        return [string]$Target.externalTraceTarget
+    }
+
+    return [string]$Target.address
+}
```

**Probe call sites stop reading `$Target.externalTraceTarget` directly:**

```diff
-    $sampleTarget = $Target.externalTraceTarget
+    $sampleTarget = Get-PSConnMonInternetProbeAddress -Target $Target
```

```diff
-    $traceTarget = $Target.externalTraceTarget
+    $traceTarget = Get-PSConnMonInternetProbeAddress -Target $Target
```

**Cycle loop iterates over both lists now:**

```diff
-    foreach ($targetValue in $Config.targets) {
+    $monitoredTargets = @()
+    if ($Config.ContainsKey('targets')) {
+        $monitoredTargets += @($Config.targets)
+    }
+    if ($Config.ContainsKey('internetTargets')) {
+        $monitoredTargets += @($Config.internetTargets)
+    }
+    foreach ($targetValue in $monitoredTargets) {
```

## Config schema diff

The schema diff from `schemas/psconnmon-config.schema.json` adds `internetTargets` to the top-level `required` array, drops `externalTraceTarget` from the required property list on each internal `target`, and introduces an entire new `internetTargets` array schema. It also drops the `minItems: 1` constraint on `targets` (because a config can now legitimately be internet-only).

```diff
-  "required": ["schemaVersion", "agent", "publish", "tests", "auth", "targets", "extensions"],
+  "required": ["schemaVersion", "agent", "publish", "tests", "auth", "targets", "internetTargets", "extensions"],
```

```diff
     "targets": {
       "type": "array",
-      "minItems": 1,
       "items": {
         "type": "object",
-        "required": ["id", "fqdn", "address", "roles", "tags", "dnsServers", "shares", "tests", "externalTraceTarget"],
+        "required": ["id", "fqdn", "address", "roles", "tags", "dnsServers", "shares", "tests"],
         "properties": {
```

```diff
-          "externalTraceTarget": {
+          "linuxProfileId": {
+            "type": "string"
+          }
+        }
+      }
+    },
+    "internetTargets": {
+      "type": "array",
+      "items": {
+        "type": "object",
+        "required": ["id", "address"],
+        "properties": {
+          "id": {
             "type": "string"
           },
-          "linuxProfileId": {
+          "name": {
+            "type": "string"
+          },
+          "address": {
             "type": "string"
+          },
+          "roles": { "type": "array", "items": { "type": "string" } },
+          "tags":  { "type": "array", "items": { "type": "string" } },
+          "tests": { "type": "array", "items": { "type": "string" } }
           }
         }
       }
```

Note: `externalTraceTarget` is removed from the required list for `targets`, and the new `internetTargets` schema requires only `id` and `address` — internet targets do **not** require an `fqdn`, `shares`, or `dnsServers`, which is exactly the asymmetry the old "everything is an internal host" model was papering over.

## Sample config diff

From `samples/config/azure-branch.psconnmon.json`. The first internal target loses `internetQuality`, `traceroute`, and its nested `externalTraceTarget: "8.8.8.8"`. The second internal target (`dc01`) similarly loses `internetQuality`, `traceroute`, and `externalTraceTarget: "1.1.1.1"`. Both values are hoisted out of the nested properties and rematerialized as two sibling entries in a brand-new `internetTargets` array:

```diff
       "tests": [
         "ping",
         "dns",
-        "share",
-        "internetQuality",
-        "traceroute"
-      ],
-      "externalTraceTarget": "8.8.8.8"
+        "share"
+      ]
     },
     {
       "id": "dc01",
       ...
       "tests": [
         "ping",
-        "dns",
+        "dns"
+      ]
+    }
+  ],
+  "internetTargets": [
+    {
+      "id": "internet-google",
+      "name": "Google DNS",
+      "address": "8.8.8.8",
+      "tests": [
         "internetQuality",
         "traceroute"
-      ],
-      "externalTraceTarget": "1.1.1.1"
+      ]
+    },
+    {
+      "id": "internet-cloudflare",
+      "name": "Cloudflare DNS",
+      "address": "1.1.1.1",
+      "tests": [
+        "internetQuality",
+        "traceroute"
+      ]
     }
   ],
```

The reshape is literal and visible: `externalTraceTarget: "8.8.8.8"` buried under an internal AD DS host becomes `{ id: "internet-google", name: "Google DNS", address: "8.8.8.8", tests: [...] }` as a sibling. Same for Cloudflare. The new samples also rename the purpose — these are no longer probes "from" a DC, they are probes *of the internet*.

## Why this is a talk-worthy moment

- **Requirements gap — Codex inferred a plausible-but-wrong model.** The initial spec/roadmap talked about "targets" as the unit of monitoring and mentioned internet quality + traceroute as **tests**. Codex logically concluded tests belonged to targets, and so traceroute's destination became a nested property (`externalTraceTarget`) on an internal target. Nothing in the spec explicitly said "traceroute is a standalone concern whose destination is itself the thing being monitored." The schema even made that nested field `required` on every target — i.e., the wrong mental model was hard-baked into validation.

- **The fix is a data-model promotion, not a probe-logic fix.** Blake didn't change how traceroute works; he changed what traceroute *is probing*. The new `internetTargets` array with `{id, name, address, tests, roles, tags}` makes internet path monitoring a first-class entity that doesn't require an internal-host host-parent. That is a small code change that implies a significant conceptual shift.

- **Backwards compatibility, even for a non-production tool.** The roadmap explicitly notes the tool isn't deployed yet, so a clean break would have been defensible. Instead the fix preserves the old `externalTraceTarget` property, keeps the `Get-PSConnMonInternetProbeAddress` fallback path, and auto-migrates legacy configs at load time — stamping each migrated entry with `tags: ['external', 'legacy-migrated']` so operators can see what was rewritten. This looks like a continuation of Codex's own strong backwards-compatibility bias, arguably stronger than the situation warranted.

- **Real-deployment feedback, not unit-test feedback.** The existing `Pester` and `pytest` suites were happy with the old nested model. The bug surfaced when Blake actually tried to deploy PSConnMon to branch sites and discovered he wanted to monitor internet paths independently of any internal host — a classic "the tests pass, the design is still wrong" moment. Note also that the whole rearchitecture ships under the commit message `updates`, with 1134 insertions across 22 files including Python service, PowerShell module, schema, samples, docs, and tests — exactly the kind of mega-commit that's easy to produce with an agent and hard to review.

- **The `legacy-migrated` tag is a nice forensic breadcrumb.** It is a live artifact in operator-facing data of the fact that an AI agent guessed wrong about the data model. Every time an operator sees `tags: ['external', 'legacy-migrated']` on an internet target, they are looking at a receipt for a requirements-specification miss.
