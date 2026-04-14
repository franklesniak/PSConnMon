# Troubleshooting Runbook

- **Status:** Active
- **Owner:** Repository Maintainers
- **Last Updated:** 2026-04-13
- **Scope:** Defines first-response troubleshooting steps for PSConnMon monitor
  and reporting service issues. Does not define postmortem policy.
- **Related:** [Architecture](../spec/architecture.md), [README](../../README.md), [Demo Runbook](demo.md)

## Agent Checks

1. Validate the config with `Test-PSConnMonConfig`.
2. Confirm `ThreadJob` is installed with `Install-Module ThreadJob -Scope CurrentUser -AllowClobber` if missing.
3. Confirm required native commands exist for the enabled probes on the current platform.
4. For Linux `domainAuth` or credentialed SMB probes, confirm `smbclient`,
   `kinit`, and `klist` are installed when the selected profile mode requires
   them.
5. Confirm any Linux secret JSON files and referenced keytabs stay under the
   config directory or `<spoolDirectory>/secrets`.
6. Inspect the local spool directory for pending JSONL batches.
7. Run `Invoke-PSConnMon -RunOnce` to isolate probe and serialization failures.

## Service Checks

1. Confirm the FastAPI process or container is running and healthy at `/healthz`.
2. Confirm the DuckDB file path is writable by the service process.
3. Confirm the configured import mode and source paths or blob settings match the deployment.
4. Check `GET /api/v1/import/status` for last-run time, backlog, and source errors.
5. Validate ingest payloads against [`schemas/psconnmon-event.schema.json`](../../schemas/psconnmon-event.schema.json) when using manual HTTP ingest.
6. Check that the dashboard has recent events and that target IDs match the monitor config.

## Azure Checks

1. Confirm the identity has blob data access on the configured storage account or container.
2. Confirm the configured config blob path exists and is valid YAML or JSON.
3. Confirm the blob prefix contains `.jsonl` files in the expected `events/<site-id>/` layout.
4. Confirm the monitor can keep using its last-known-good config if Azure polling fails.
5. Inspect retained local batch files before forcing any cleanup action.

## Common Failure Modes

- Missing Linux SMB tooling should surface as `SKIPPED`, not a process crash.
- Missing `kinit` or `klist` should surface as `SKIPPED` for Linux Kerberos
  workflows, not a process crash.
- Share failures should not block ping, DNS, traceroute, or internet-quality probes.
- Manual `tracert` success does not guarantee collector success if the overall
  traceroute job timeout is too low. Compare `tests.tracerouteTimeoutSeconds`
  with `tests.tracerouteProbeTimeoutSeconds`, especially on Windows.
- Dashboard gaps usually indicate import, ingest, or timestamp issues before they indicate query problems.
- Route visualization anomalies usually indicate missing traceroute events or inconsistent path hashes.
