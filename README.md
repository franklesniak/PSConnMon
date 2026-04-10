# PSConnMon

A lightweight, cross-platform PowerShell connectivity monitor that continuously
tests ICMP, DNS, SMB, and path health against target systems and logs results to
structured local batches. Built for sysadmins and network engineers who need
always-on visibility, with an optional Python reporting service for dashboards,
path visualization, and centralized views.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Parameters](#parameters)
- [Configuration](#configuration)
- [Log Output](#log-output)
- [Reporting Service](#reporting-service)
- [Azure Deployment](#azure-deployment)
- [Use Cases](#use-cases)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **ICMP Ping** — Continuous latency checks by IP address and FQDN
- **DNS Lookups** — Queries via configured DNS servers or the local primary DNS
  server
- **SMB Share Probes** — Lightweight share accessibility tests with bounded
  timeouts
- **Traceroute / Path Tracking** — Hop-by-hop path capture for route-change and
  latency analysis
- **Structured Batch Logging** — JSONL spool files for local retention, replay,
  and upload
- **Optional CSV Mirror** — CSV output for operators that still want flat-file
  review
- **Flexible Input Models** — YAML/JSON configuration files or direct
  PowerShell target objects
- **Cross-Platform** — PowerShell on Windows, macOS, and Linux, with
  platform-aware dependency checks and graceful probe fallback
- **Optional Reporting Service** — FastAPI + DuckDB dashboard for summaries,
  incidents, and PingPlotter-style path views

---

## Requirements

| Requirement | Details |
| --- | --- |
| **PowerShell** | Windows PowerShell 5.1+ or PowerShell 7.x |
| **OS** | Windows, macOS, and Linux |
| **Module** | [ThreadJob](https://www.powershellgallery.com/packages/ThreadJob) |
| **Optional YAML** | `ConvertFrom-Yaml` / `ConvertTo-Yaml` support for YAML config files |
| **Optional Linux tools** | `smbclient`, `traceroute`, `dig` or `nslookup` |
| **Optional reporting service** | Python 3.13 for the FastAPI dashboard |

Install the required PowerShell module:

```powershell
Install-Module ThreadJob -Scope CurrentUser -AllowClobber
```

Install the optional Python reporting service dependencies:

```bash
pip install -e ".[dev]"
```

---

## Quick Start

### Modern Config Workflow

```powershell
Import-Module ./PSConnMon/PSConnMon.psd1 -Force
Export-PSConnMonSampleConfig -Path ./samples/config/sample.psconnmon.yaml -Force
.\Watch-Network.ps1 -ConfigPath ./samples/config/sample.psconnmon.yaml -RunOnce
```

### Direct PowerShell Object Workflow

```powershell
$targets = @(
    @{
        id = 'loopback'
        fqdn = 'localhost'
        address = '127.0.0.1'
        tests = @('ping')
    }
)

.\Watch-Network.ps1 `
    -Targets $targets `
    -Agent @{ agentId = 'ops-01'; siteId = 'lab'; spoolDirectory = 'data/spool' } `
    -Tests @{ enabled = @('ping') } `
    -RunOnce
```

Press **Ctrl+C** to stop. Local spool files are written under the configured
spool directory.

---

## Parameters

`Watch-Network.ps1` supports a config-file workflow and a direct object workflow.

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `ConfigPath` | Yes (config mode) | — | YAML or JSON config file |
| `Targets` | Yes (object mode) | — | Array of target objects matching the `targets` config section |
| `Agent` | No | Defaults applied | Object matching the `agent` config section |
| `Publish` | No | Defaults applied | Object matching the `publish` config section |
| `Tests` | No | Defaults applied | Object matching the `tests` config section |
| `Auth` | No | Defaults applied | Object matching the `auth` config section |
| `Extensions` | No | `@()` | Array matching the `extensions` config section |
| `RunOnce` | No | Off | Execute one cycle and exit |
| `MaxRuntimeMinutes` | No | `0` | Auto-stop after N minutes (`0` = indefinite) |

---

## Configuration

The modern workflow uses a structured config with these top-level sections:

- `agent`
- `publish`
- `tests`
- `auth`
- `targets`
- `extensions`

YAML is the recommended operator format when `ConvertFrom-Yaml` is available.
JSON remains supported and is the lowest-dependency option.

Useful files:

- [`samples/config/local-lab.psconnmon.yaml`](samples/config/local-lab.psconnmon.yaml)
- [`samples/config/azure-branch.psconnmon.yaml`](samples/config/azure-branch.psconnmon.yaml)
- [`schemas/psconnmon-config.schema.json`](schemas/psconnmon-config.schema.json)

### Object Input Shape

When using `-Targets`, each target object should match the same structure used in
the file-based config:

| Property | Required | Description |
| --- | --- | --- |
| `id` | Yes | Stable target identifier |
| `fqdn` | Yes | Hostname used for DNS and reporting |
| `address` | Yes | IP address or probe target address |
| `tests` | No | Enabled tests for the target |
| `dnsServers` | No | DNS servers to query for DNS probes |
| `shares` | No | Share definitions with `id` and `path` |
| `roles` | No | Informational target roles |
| `tags` | No | Informational tags |
| `externalTraceTarget` | No | Address used for internet-quality and traceroute probes |

Top-level object parameters align to the same config sections:

| Parameter | Purpose |
| --- | --- |
| `-Agent` | Monitor identity, spool path, intervals, and runtime settings |
| `-Publish` | Local/Azure publish behavior and CSV mirror settings |
| `-Tests` | Global probe settings such as timeouts and sample counts |
| `-Auth` | Authentication-related options such as Linux SMB mode |
| `-Extensions` | Trusted local extension probes referenced by file path |

### File Config Options

The current file/object configuration model supports these main option groups:

- `agent.agentId`, `agent.siteId`, `agent.spoolDirectory`, `agent.batchSize`,
  `agent.publishIntervalSeconds`, `agent.configPollIntervalSeconds`,
  `agent.cycleIntervalSeconds`, `agent.maxRuntimeMinutes`,
  `agent.cleanupAfterDays`
- `publish.mode`, `publish.format`, `publish.csvMirror`,
  `publish.azure.enabled`, `publish.azure.accountName`,
  `publish.azure.containerName`, `publish.azure.blobPrefix`,
  `publish.azure.configBlobPath`, `publish.azure.authMode`,
  `publish.azure.sasToken`
- `tests.enabled`, `tests.pingTimeoutMs`, `tests.pingPacketSize`,
  `tests.shareAccessTimeoutSeconds`, `tests.tracerouteTimeoutSeconds`,
  `tests.internetQualitySampleCount`
- `auth.linuxSmbMode`, `auth.secretReference`
- `extensions[].id`, `extensions[].path`, `extensions[].entryPoint`,
  `extensions[].enabled`, `extensions[].targets`

`auth.secretReference` is reserved for future credential-backed probes and does
not power built-in Linux SMB probing in v1. Built-in Linux SMB remains
`currentContext` only.

### Extension Contract

Extensions are local PowerShell scripts referenced by path. They are intended
for site-specific probes without modifying the core module.

- Inline script text in YAML or JSON is not supported.
- Extension paths must stay under the config directory or
  `<spoolDirectory>/extensions`.
- Each extension must define an `id` and `path`.
- `entryPoint` defaults to `Invoke-PSConnMonExtension`.
- Extension scripts must return one event or an array of events. Partial event
  objects are accepted and normalized into canonical PSConnMon events.

Examples:

- [`samples/config/extensions/Invoke-SampleProbe.ps1`](samples/config/extensions/Invoke-SampleProbe.ps1)
- [`samples/config/local-lab.psconnmon.yaml`](samples/config/local-lab.psconnmon.yaml)

---

## Log Output

PSConnMon writes JSONL batches into the configured spool directory. When
`publish.csvMirror` is enabled, a CSV mirror is also written for operator
convenience.

Each event includes explicit target identity and normalized result fields such
as:

- `timestampUtc`
- `agentId`
- `siteId`
- `targetId`
- `fqdn`
- `targetAddress`
- `testType`
- `probeName`
- `result`
- `details`

Traceroute events also include hop-level fields such as `hopIndex`,
`hopAddress`, `hopLatencyMs`, and `pathHash`.

---

## Reporting Service

The optional reporting service is a small FastAPI application backed by DuckDB.
It provides:

- `POST /api/v1/import/run`
- `GET /api/v1/import/status`
- `POST /api/v1/ingest/batches`
- `GET /api/v1/summary`
- `GET /api/v1/targets`
- `GET /api/v1/paths`
- `GET /api/v1/incidents`
- `GET /` for the built-in dashboard

### Service Configuration

| Input | Default | Description |
| --- | --- | --- |
| `PSCONNMON_DB_PATH` | `data/psconnmon.duckdb` | DuckDB database path used by the reporting service |
| `PSCONNMON_IMPORT_MODE` | `local` | Import mode: `disabled`, `local`, `azure`, or `hybrid` |
| `PSCONNMON_IMPORT_INTERVAL_SECONDS` | `30` | Scheduled import interval in seconds |
| `PSCONNMON_IMPORT_LOCAL_PATH` | `data/import` | Root path scanned for local `.jsonl` batches |
| `PSCONNMON_AZURE_STORAGE_ACCOUNT` | — | Azure Storage account name for blob imports |
| `PSCONNMON_AZURE_STORAGE_CONTAINER` | — | Azure blob container for imports |
| `PSCONNMON_AZURE_BLOB_PREFIX` | `events` | Blob prefix scanned for `.jsonl` batches |
| `PSCONNMON_AZURE_AUTH_MODE` | `managedIdentity` | Azure auth mode: `managedIdentity` or `sasToken` |
| `PSCONNMON_AZURE_SAS_TOKEN` | — | SAS token used when `PSCONNMON_AZURE_AUTH_MODE=sasToken` |
| `PSCONNMON_AZURE_BLOB_SERVICE_URL` | — | Optional blob service URL override for emulators such as Azurite |
| Service port | `8080` | HTTP listen port used by the local runner and container |

### Ingestion Model

The reporting service uses a pull-based import model:

1. The PowerShell monitor writes JSONL batches locally.
2. Deployed monitors can upload those batches to Azure Blob Storage.
3. The reporting service imports batches on a schedule from a local directory,
   Azure Blob Storage, or both.
4. DuckDB remains the query store for the dashboard and APIs.

`POST /api/v1/ingest/batches` remains available for manual seeding and tests.
`POST /api/v1/import/run` forces an immediate import cycle, and
`GET /api/v1/import/status` shows freshness, lag, and last-error state per
source.

Start it locally with:

```bash
python -m psconnmon_service
```

Or use the containerized deployment:

```bash
docker compose up --build
```

Seed the dashboard with example data if needed:

- [`samples/ingest/sample-batch.json`](samples/ingest/sample-batch.json)
- JSONL batches dropped under the configured local import path

---

## Azure Deployment

Terraform assets for Azure Container Apps, managed identity, and optional
storage-backed control-plane resources live in
[`infra/terraform/azure`](infra/terraform/azure).

Key Terraform inputs are documented in
[`infra/terraform/azure/variables.tf`](infra/terraform/azure/variables.tf). The
main deployment toggles are:

- `deploy_storage`
- `deploy_container_app`
- `existing_storage_account_name`
- `existing_storage_account_id`
- `existing_storage_container_name`
- `container_image`
- `container_app_port`
- `container_app_db_path`
- `container_app_import_mode`
- `container_app_import_interval_seconds`
- `container_app_import_local_path`
- `container_app_blob_prefix`
- `container_app_azure_auth_mode`
- `container_app_cpu`
- `container_app_memory`
- `container_app_min_replicas`
- `container_app_max_replicas`

Use the standard workflow:

```bash
terraform -chdir=infra/terraform/azure init
terraform -chdir=infra/terraform/azure validate
terraform -chdir=infra/terraform/azure plan -var-file=demo.tfvars
terraform -chdir=infra/terraform/azure apply -var-file=demo.tfvars
```

---

## Use Cases

### Scheduled Diagnostics

Run a time-limited monitoring session via Task Scheduler, cron, or a service
manager using either a config file or direct object input.

### Distributed Monitoring

Deploy to branch offices, plants, labs, or lightweight endpoints to monitor
connectivity back to shared infrastructure. Keep local spool data on the node
or upload batches for centralized dashboards.

---

## Roadmap

See [`PSConnMon_Roadmap.md`](PSConnMon_Roadmap.md)
for the current implementation roadmap and
[`docs/spec/requirements.md`](docs/spec/requirements.md)
for the mapped requirements.

---

## Contributing

Contributions are welcome. Please see
[`CONTRIBUTING.md`](CONTRIBUTING.md)
for guidelines.

---

## License

This project is licensed under the MIT License. See
[`LICENSE`](LICENSE) for details.
