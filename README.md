# PSConnMon

A lightweight, cross-platform PowerShell connectivity monitor that continuously
tests ICMP, DNS, and SMB against target servers and logs results to CSV. Built
for sysadmins and network engineers who need always-on visibility. Deploy across
a fleet of small devices for distributed network health monitoring.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Parameters](#parameters)
- [Log Output](#log-output)
- [Use Cases](#use-cases)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **ICMP Ping** — Continuous pings by both IP address and FQDN to a file server
  and domain controller
- **DNS Lookups** — Queries via the primary NIC DNS server and the domain
  controller's DNS, bypassing cache
- **SMB Share Probes** — Lightweight share accessibility tests (Windows only)
- **CSV Logging** — Quarter-hour CSV logs per test category, plus hourly
  error-only CSVs
- **Automatic Log Rotation** — 48-hour retention with automatic cleanup of older
  files
- **Configurable Intervals** — Check frequency, ping packet size, ping timeout,
  and share access timeout are all adjustable
- **Timed Runs** — Optional `MaxRuntimeMinutes` parameter for scheduled
  diagnostics
- **Cross-Platform** — Windows PowerShell 5.1+ and PowerShell 7.4+/7.5+ on
  Windows, macOS, and Linux

---

## Requirements

| Requirement | Details |
| --- | --- |
| **PowerShell** | Windows PowerShell 5.1 (.NET Framework 4.6.2+) or PowerShell 7.4.x / 7.5.x |
| **OS** | Windows (all features), macOS and Linux (PowerShell 7.x; SMB probes are Windows-only) |
| **Module** | [ThreadJob](https://www.powershellgallery.com/packages/ThreadJob) |

Install the required module:

```powershell
Install-Module -Name ThreadJob -Scope CurrentUser -Force
```

---

## Quick Start

```powershell
.\Watch-Network.ps1 `
    -FileServerFQDN FILE1.corp.local `
    -FileServerIP 10.1.2.3 `
    -FileServerShare '\\FILE1.corp.local\Plant' `
    -DomainControllerFQDN DC1.corp.local `
    -DomainControllerIP 10.1.0.10 `
    -DomainControllerShare '\\DC1.corp.local\TestShare' `
    -LogDirectory C:\Logs\ConnMon
```

Press **Ctrl+C** to stop. Logs are written to subdirectories under the specified
`LogDirectory`.

---

## Parameters

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `FileServerFQDN` | Yes | — | FQDN of the file server to monitor |
| `FileServerIP` | Yes | — | IP address of the file server |
| `FileServerShare` | Yes | — | UNC path to the file server share |
| `DomainControllerFQDN` | Yes | — | FQDN of the domain controller |
| `DomainControllerIP` | Yes | — | IP address of the domain controller |
| `DomainControllerShare` | Yes | — | UNC path to the domain controller test share |
| `LogDirectory` | Yes | — | Root directory for log files |
| `PrimaryDNSServer` | No | Auto-detect | IP of the primary DNS server |
| `CheckFrequency` | No | `2500` | Check interval in milliseconds (500–60000) |
| `PingPacketSize` | No | `56` | ICMP payload size in bytes (32–65500) |
| `PingTimeout` | No | `3000` | Ping timeout in milliseconds (500–10000) |
| `ShareAccessTimeout` | No | `15000` | SMB probe timeout in milliseconds (5000–60000) |
| `MaxRuntimeMinutes` | No | `0` | Auto-stop after N minutes (0 = indefinite) |

---

## Log Output

Logs are organized into subdirectories under `LogDirectory`:

| Log Type | Rotation | Description |
| --- | --- | --- |
| **Ping** | Every 15 minutes | ICMP results (roundtrip time, resolved IP, status) |
| **DNS** | Every 15 minutes | DNS lookup results via primary and DC DNS servers |
| **SMB** | Every 15 minutes | Share access probe results (Windows only) |
| **Errors** | Every hour | Consolidated error-only log across all test types |

All logs are CSV-formatted. Files older than 48 hours are automatically purged.

---

## Use Cases

### Scheduled Diagnostics

Run a time-limited monitoring session via Task Scheduler or cron:

```powershell
.\Watch-Network.ps1 `
    -FileServerFQDN FILE1.corp.local `
    -FileServerIP 10.1.2.3 `
    -FileServerShare '\\FILE1.corp.local\Plant' `
    -DomainControllerFQDN DC1.corp.local `
    -DomainControllerIP 10.1.0.10 `
    -DomainControllerShare '\\DC1.corp.local\TestShare' `
    -LogDirectory C:\Logs\ConnMon `
    -MaxRuntimeMinutes 60
```

### Remote Site Monitoring

Deploy to small devices (e.g., Raspberry Pi) at branch offices to continuously
monitor connectivity to central infrastructure. Collect logs centrally for
fleet-wide visibility.

---

## Roadmap

- [ ] **Traceroute / Internet quality monitoring** — Perform traceroutes to
  external addresses (e.g., 8.8.8.8) and store hop-by-hop results over time,
  similar to PingPlotter
- [ ] **Centralized logging** — Upload results to Azure Storage Accounts (or
  other cloud backends) for fleet-wide aggregation and dashboarding
- [ ] **Raspberry Pi optimization** — First-class support for lightweight,
  disposable monitoring agents deployed across many locations
- [ ] **PowerShell module** — Publish to the
  [PowerShell Gallery](https://www.powershellgallery.com/) for easy installation
  via `Install-Module`
- [ ] **Configurable targets** — Support arbitrary target lists beyond a single
  file server and domain controller pair

---

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for
details.
