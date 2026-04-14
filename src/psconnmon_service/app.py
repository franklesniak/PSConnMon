"""FastAPI application for PSConnMon reporting."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse

from . import __version__
from .config import ServiceSettings
from .importer import ImportManager
from .models import DashboardSnapshot, FleetSummary, ImportStatus, IngestBatch, TargetDetail
from .storage import StorageRepository
from .ui import render_dashboard


def create_app(
    database_path: str | None = None, settings: ServiceSettings | None = None
) -> FastAPI:
    """Create the PSConnMon reporting application."""

    if settings is not None and database_path is not None:
        raise ValueError(
            "create_app() accepts either 'settings' or 'database_path', not both. "
            "Pass a fully constructed ServiceSettings via 'settings' when overriding."
        )

    resolved_settings = settings or ServiceSettings.from_env(database_path_override=database_path)
    repository = StorageRepository(resolved_settings.database_path)
    import_manager = ImportManager(repository, resolved_settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
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

    app = FastAPI(title="PSConnMon", version=__version__, lifespan=lifespan)
    app.state.repository = repository
    app.state.import_manager = import_manager
    app.state.settings = resolved_settings

    def resolve_window_minutes(
        summary_window_minutes: int | None, summary_window_hours: int | None
    ) -> int | None:
        """Prefer explicit minute windows while preserving hour-based compatibility."""

        if summary_window_minutes is not None:
            return summary_window_minutes or None
        if summary_window_hours is not None:
            return (summary_window_hours * 60) or None
        return 24 * 60

    def build_dashboard_snapshot(summary_window_minutes: int | None = 24 * 60) -> DashboardSnapshot:
        """Build the full live-dashboard payload from repository state."""

        return DashboardSnapshot(
            summary=repository.get_fleet_summary(window_minutes=summary_window_minutes),
            agents=repository.list_agents(),
            sites=repository.list_sites(),
            targets=repository.list_targets(),
            paths=repository.list_paths(),
            path_changes=repository.list_path_changes(),
            incidents=repository.list_incidents(),
            import_status=repository.get_import_status(resolved_settings.import_mode),
            refreshed_utc=datetime.now(timezone.utc),
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

    @app.get("/api/v1/import/status", response_model=ImportStatus, response_model_by_alias=False)
    def get_import_status() -> ImportStatus:
        return repository.get_import_status(resolved_settings.import_mode)

    @app.get("/api/v1/summary", response_model=FleetSummary, response_model_by_alias=False)
    def get_summary(
        summary_window_minutes: int | None = Query(default=None, ge=0),
        summary_window_hours: int | None = Query(default=None, ge=0),
    ) -> FleetSummary:
        return repository.get_fleet_summary(
            window_minutes=resolve_window_minutes(summary_window_minutes, summary_window_hours)
        )

    @app.get("/api/v1/dashboard", response_model=DashboardSnapshot, response_model_by_alias=False)
    def get_dashboard_snapshot(
        summary_window_minutes: int | None = Query(default=None, ge=0),
        summary_window_hours: int | None = Query(default=None, ge=0),
    ) -> DashboardSnapshot:
        return build_dashboard_snapshot(
            summary_window_minutes=resolve_window_minutes(
                summary_window_minutes, summary_window_hours
            )
        )

    @app.get("/api/v1/agents")
    def get_agents() -> list[dict[str, object]]:
        return [agent.model_dump(mode="json") for agent in repository.list_agents()]

    @app.get("/api/v1/sites")
    def get_sites() -> list[dict[str, object]]:
        return [site.model_dump(mode="json") for site in repository.list_sites()]

    @app.get("/api/v1/targets")
    def get_targets() -> list[dict[str, object]]:
        return [target.model_dump(mode="json") for target in repository.list_targets()]

    @app.get(
        "/api/v1/targets/{target_key}", response_model=TargetDetail, response_model_by_alias=False
    )
    def get_target_detail(
        target_key: str,
        window_minutes: int | None = Query(default=None, ge=0),
        window_hours: int | None = Query(default=None, ge=0),
    ) -> TargetDetail:
        detail = repository.get_target_detail(
            target_key,
            window_minutes=resolve_window_minutes(window_minutes, window_hours),
        )
        if detail is None:
            raise HTTPException(status_code=404, detail=f"Unknown target '{target_key}'.")
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
