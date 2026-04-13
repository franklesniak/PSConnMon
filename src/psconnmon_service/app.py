"""FastAPI application for PSConnMon reporting."""

from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse

from .config import ServiceSettings
from .importer import ImportManager
from .models import DashboardSnapshot, FleetSummary, ImportStatus, IngestBatch, TargetDetail
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

    def build_dashboard_snapshot() -> DashboardSnapshot:
        """Build the full live-dashboard payload from repository state."""

        return DashboardSnapshot(
            summary=repository.get_fleet_summary(),
            agents=repository.list_agents(),
            sites=repository.list_sites(),
            targets=repository.list_targets(),
            paths=repository.list_paths(),
            path_changes=repository.list_path_changes(),
            incidents=repository.list_incidents(),
            importStatus=repository.get_import_status(resolved_settings.import_mode),
            refreshedUtc=datetime.now(timezone.utc),
        )

    @app.get("/healthz")
    def get_health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/", response_class=HTMLResponse)
    def get_dashboard() -> str:
        return render_dashboard(build_dashboard_snapshot())

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

    @app.get("/api/v1/dashboard", response_model=DashboardSnapshot)
    def get_dashboard_snapshot() -> DashboardSnapshot:
        return build_dashboard_snapshot()

    @app.get("/api/v1/agents")
    def get_agents() -> list[dict[str, object]]:
        return [agent.model_dump(mode="json") for agent in repository.list_agents()]

    @app.get("/api/v1/sites")
    def get_sites() -> list[dict[str, object]]:
        return [site.model_dump(mode="json") for site in repository.list_sites()]

    @app.get("/api/v1/targets")
    def get_targets() -> list[dict[str, object]]:
        return [target.model_dump(mode="json") for target in repository.list_targets()]

    @app.get("/api/v1/targets/{target_id}", response_model=TargetDetail)
    def get_target_detail(target_id: str) -> TargetDetail:
        detail = repository.get_target_detail(target_id)
        if detail is None:
            raise HTTPException(status_code=404, detail=f"Unknown target '{target_id}'.")
        return detail

    @app.get("/api/v1/paths")
    def get_paths() -> list[dict[str, object]]:
        return [path.model_dump(mode="json") for path in repository.list_paths()]

    @app.get("/api/v1/path-changes")
    def get_path_changes() -> list[dict[str, object]]:
        return [change.model_dump(mode="json") for change in repository.list_path_changes()]

    @app.get("/api/v1/incidents")
    def get_incidents() -> list[dict[str, object]]:
        return [incident.model_dump(mode="json") for incident in repository.list_incidents()]

    return app


app = create_app()
