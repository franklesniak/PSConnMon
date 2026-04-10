"""Runtime configuration helpers for the PSConnMon reporting service."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


VALID_IMPORT_MODES = {"disabled", "local", "azure", "hybrid"}
VALID_AZURE_AUTH_MODES = {"managedIdentity", "sasToken"}


@dataclass(frozen=True)
class ServiceSettings:
    """Resolved runtime settings for the reporting service."""

    database_path: Path
    import_mode: str
    import_interval_seconds: int
    import_local_path: Path
    azure_storage_account: str
    azure_storage_container: str
    azure_blob_prefix: str
    azure_auth_mode: str
    azure_sas_token: str
    azure_blob_service_url: str

    @classmethod
    def from_env(cls, database_path_override: str | None = None) -> "ServiceSettings":
        """Read service settings from environment variables."""

        import_mode = os.getenv("PSCONNMON_IMPORT_MODE", "local")
        if import_mode not in VALID_IMPORT_MODES:
            raise ValueError(
                f"Unsupported PSCONNMON_IMPORT_MODE '{import_mode}'. "
                f"Expected one of: {', '.join(sorted(VALID_IMPORT_MODES))}."
            )

        azure_auth_mode = os.getenv("PSCONNMON_AZURE_AUTH_MODE", "managedIdentity")
        if azure_auth_mode not in VALID_AZURE_AUTH_MODES:
            raise ValueError(
                f"Unsupported PSCONNMON_AZURE_AUTH_MODE '{azure_auth_mode}'. "
                f"Expected one of: {', '.join(sorted(VALID_AZURE_AUTH_MODES))}."
            )

        interval_text = os.getenv("PSCONNMON_IMPORT_INTERVAL_SECONDS", "30")
        try:
            import_interval_seconds = int(interval_text)
        except ValueError as error:
            raise ValueError(
                "PSCONNMON_IMPORT_INTERVAL_SECONDS must be an integer."
            ) from error

        if import_interval_seconds < 1:
            raise ValueError("PSCONNMON_IMPORT_INTERVAL_SECONDS must be greater than 0.")

        return cls(
            database_path=Path(
                database_path_override or os.getenv("PSCONNMON_DB_PATH", "data/psconnmon.duckdb")
            ),
            import_mode=import_mode,
            import_interval_seconds=import_interval_seconds,
            import_local_path=Path(os.getenv("PSCONNMON_IMPORT_LOCAL_PATH", "data/import")),
            azure_storage_account=os.getenv("PSCONNMON_AZURE_STORAGE_ACCOUNT", ""),
            azure_storage_container=os.getenv("PSCONNMON_AZURE_STORAGE_CONTAINER", ""),
            azure_blob_prefix=os.getenv("PSCONNMON_AZURE_BLOB_PREFIX", "events"),
            azure_auth_mode=azure_auth_mode,
            azure_sas_token=os.getenv("PSCONNMON_AZURE_SAS_TOKEN", ""),
            azure_blob_service_url=os.getenv("PSCONNMON_AZURE_BLOB_SERVICE_URL", ""),
        )
