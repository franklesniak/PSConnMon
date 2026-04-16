# Healthcheck Endpoint

This document explains what the PSConnMon reporting service healthcheck does, what it does not do, and how to interpret it during deployment and troubleshooting.

## Endpoint

The reporting service exposes a simple HTTP healthcheck at:

```text
/healthz
```

Example:

```bash
curl http://localhost:8080/healthz
```

Expected response:

```json
{"status":"ok"}
```

## What It Actually Checks

Today, `/healthz` is a process-level liveness check.

Its implementation is intentionally simple:

- the FastAPI application is running
- the HTTP server can accept a request
- the route handler can return a successful response

In code, the endpoint is defined here:

- [app.py](/Users/blake/CodeDev/conference/PSConnMon/src/psconnmon_service/app.py:87)

It currently returns a static payload:

```python
@app.get("/healthz")
def get_health() -> dict[str, str]:
    return {"status": "ok"}
```

## What It Does Not Check

A `200 OK` from `/healthz` does not mean the whole reporting pipeline is healthy.

It does not verify:

- that DuckDB contains recent data
- that Azure Blob import is succeeding
- that the importer is current or caught up
- that collectors are still publishing fresh batches
- that the dashboard payload can be built successfully
- that the configured storage account, SAS token, or managed identity are valid
- that the latest imported data is within an acceptable freshness window

This is the main source of confusion: `/healthz` confirms the service is alive, not that the monitoring system is end-to-end healthy.

## Practical Interpretation

Use `/healthz` to answer this narrow question:

> Is the reporting web service up and responding to HTTP requests?

Do not use it to answer broader questions like:

- Is the dashboard current?
- Are collectors publishing successfully?
- Is Azure import working?
- Is the database fresh?

For those questions, use the additional endpoints below.

## Better Operational Checks

### Import status

Use this to confirm whether the importer is running and whether recent runs are succeeding:

```bash
curl http://localhost:8080/api/v1/import/status
```

This is the best current endpoint for checking importer state.

Look for:

- `mode`
- `last_run_utc`
- `last_success_utc`
- `last_error`
- per-source counters and backlog values

### Fleet summary

Use this to confirm the service can query the database and return current summary data:

```bash
curl "http://localhost:8080/api/v1/summary?summary_window_minutes=60"
```

This helps answer whether the service has recent events to work with.

### Dashboard payload

Use this when validating the end-user experience:

```bash
curl "http://localhost:8080/api/v1/dashboard?summary_window_minutes=60"
```

If `/healthz` succeeds but `/api/v1/dashboard` fails, the service is alive but the dashboard path is broken or the underlying data/model contract is inconsistent.

## Suggested Deployment Validation

When bringing up the dashboard container or service, validate in this order:

1. Check liveness:

```bash
curl http://localhost:8080/healthz
```

1. Check importer state:

```bash
curl http://localhost:8080/api/v1/import/status
```

1. Check summary data:

```bash
curl "http://localhost:8080/api/v1/summary?summary_window_minutes=60"
```

1. Check full dashboard payload:

```bash
curl "http://localhost:8080/api/v1/dashboard?summary_window_minutes=60"
```

That sequence separates:

- service down
- importer broken
- data stale
- dashboard/query/rendering issues

## During The Summit Demo

If you want a clean explanation in the demo, the simplest phrasing is:

> `/healthz` is only a liveness probe for the reporting service. It tells us the web app is up, not that telemetry ingestion is fresh or that the dashboard data is current.

Then immediately pair it with:

```bash
curl http://localhost:8080/api/v1/import/status
```

That gives the audience a more complete picture.

## Future Improvement

If you want a stronger operational signal later, a separate readiness-style endpoint would be better than overloading `/healthz`.

For example, a future `/readyz` could validate:

- database open succeeds
- importer state can be read
- latest successful import is not older than a threshold
- dashboard snapshot can be built

That would preserve the current meaning of `/healthz` while adding a more actionable health signal for real operations.
