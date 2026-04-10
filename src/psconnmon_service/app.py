"""FastAPI application for PSConnMon reporting."""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import HTMLResponse

from .config import ServiceSettings
from .importer import ImportManager
from .models import FleetSummary, ImportStatus, IngestBatch
from .storage import StorageRepository
from .ui import render_dashboard


def create_app(
    database_path: str | None = None, settings: ServiceSettings | None = None
) -> FastAPI:
    """Create the PSConnMon reporting application."""

    resolved_settings = settings or ServiceSettings.from_env(database_path_override=database_path)
    repository = StorageRepository(resolved_settings.database_path)
    import_manager = ImportManager(repository, resolved_settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        await asyncio.to_thread(import_manager.run_once)
        import_task = None
        if resolved_settings.import_mode != "disabled":
            import_task = asyncio.create_task(import_manager.run_forever())

        try:
            yield
        finally:
            import_manager.stop()
            if import_task is not None:
                await import_task

    app = FastAPI(title="PSConnMon", version="0.3.0", lifespan=lifespan)
    app.state.repository = repository
    app.state.import_manager = import_manager
    app.state.settings = resolved_settings

    @app.get("/healthz")
    def get_health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/", response_class=HTMLResponse)
    def get_dashboard() -> str:
        summary = repository.get_fleet_summary()
        return render_dashboard(
            summary=summary,
            targets=repository.list_targets(),
            paths=repository.list_paths(),
            incidents=repository.list_incidents(),
            import_status=repository.get_import_status(resolved_settings.import_mode),
        )

    @app.post("/api/v1/ingest/batches")
    def ingest_batch(batch: IngestBatch) -> dict[str, int]:
        inserted = repository.ingest_events(batch.events)
        return {"inserted": inserted}

    @app.post("/api/v1/import/run")
    def run_import() -> dict[str, int | str]:
        status = import_manager.run_once()
        return {
            "mode": status.mode,
            "discovered": sum(source.last_run_discovered for source in status.sources),
            "imported": sum(source.last_run_imported for source in status.sources),
            "skipped": sum(source.last_run_skipped for source in status.sources),
            "failed": sum(source.last_run_failed for source in status.sources),
        }

    @app.get("/api/v1/import/status", response_model=ImportStatus)
    def get_import_status() -> ImportStatus:
        return repository.get_import_status(resolved_settings.import_mode)

    @app.get("/api/v1/summary", response_model=FleetSummary)
    def get_summary() -> FleetSummary:
        return repository.get_fleet_summary()

    @app.get("/api/v1/targets")
    def get_targets() -> list[dict[str, object]]:
        return [target.model_dump(mode="json") for target in repository.list_targets()]

    @app.get("/api/v1/paths")
    def get_paths() -> list[dict[str, object]]:
        return [path.model_dump(mode="json") for path in repository.list_paths()]

    @app.get("/api/v1/incidents")
    def get_incidents() -> list[dict[str, object]]:
        return [incident.model_dump(mode="json") for incident in repository.list_incidents()]

    return app


app = create_app()
