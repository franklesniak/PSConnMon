"""Import workers for local and Azure-backed PSConnMon event batches."""

from __future__ import annotations

import asyncio
import hashlib
import json
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

from .config import ServiceSettings
from .models import EventRecord, ImportStatus
from .storage import StorageRepository


@dataclass(frozen=True)
class ImportBatch:
    """A discovered JSONL batch ready for validation and ingest."""

    source_type: str
    source_identifier: str
    fingerprint: str
    content: str


class BatchSource(Protocol):
    """Protocol for import batch enumerators."""

    source_type: str

    def iter_batches(self) -> list[ImportBatch]:
        """Return the currently discoverable batches for this source."""


def _build_file_fingerprint(content: str) -> str:
    """Create a stable SHA-256 fingerprint for local batch content."""

    return hashlib.sha256(content.encode("utf-8")).hexdigest()


class LocalBatchSource:
    """Enumerate JSONL files from a local import directory."""

    source_type = "local"

    def __init__(self, root_path: Path) -> None:
        self.root_path = root_path

    def iter_batches(self) -> list[ImportBatch]:
        """Return discoverable local JSONL files under the configured root."""

        resolved_root = self.root_path.resolve()
        if not resolved_root.exists():
            resolved_root.mkdir(parents=True, exist_ok=True)
            return []

        batches: list[ImportBatch] = []
        for file_path in sorted(resolved_root.rglob("*.jsonl")):
            if file_path.is_symlink() or not file_path.is_file():
                continue

            resolved_path = file_path.resolve()
            if resolved_path != resolved_root and resolved_root not in resolved_path.parents:
                continue

            content = resolved_path.read_text(encoding="utf-8")
            relative_identifier = resolved_path.relative_to(resolved_root).as_posix()
            batches.append(
                ImportBatch(
                    source_type=self.source_type,
                    source_identifier=relative_identifier,
                    fingerprint=_build_file_fingerprint(content),
                    content=content,
                )
            )

        return batches


class AzureBlobBatchSource:
    """Enumerate JSONL batches from Azure Blob Storage using the official SDK."""

    source_type = "azure"

    def __init__(self, settings: ServiceSettings) -> None:
        self.settings = settings

    def iter_batches(self) -> list[ImportBatch]:
        """Return discoverable Azure blob batches from the configured prefix."""

        blob_service_client = self._create_blob_service_client()
        container_client = blob_service_client.get_container_client(
            self.settings.azure_storage_container
        )
        prefix = self.settings.azure_blob_prefix.strip("/")
        list_prefix = "" if prefix == "" else f"{prefix}/"

        batches: list[ImportBatch] = []
        for blob in container_client.list_blobs(name_starts_with=list_prefix):
            blob_name = getattr(blob, "name", "")
            if not blob_name.endswith(".jsonl"):
                continue

            raw_bytes = container_client.download_blob(blob_name).readall()
            content = raw_bytes.decode("utf-8")
            etag = str(getattr(blob, "etag", "")).strip('"')
            batches.append(
                ImportBatch(
                    source_type=self.source_type,
                    source_identifier=blob_name,
                    fingerprint=etag or _build_file_fingerprint(content),
                    content=content,
                )
            )

        return batches

    def _create_blob_service_client(self) -> Any:
        """Create an Azure BlobServiceClient using managed identity or SAS."""

        if self.settings.azure_storage_account == "":
            raise ValueError("PSCONNMON_AZURE_STORAGE_ACCOUNT is required for Azure import mode.")

        if self.settings.azure_storage_container == "":
            raise ValueError("PSCONNMON_AZURE_STORAGE_CONTAINER is required for Azure import mode.")

        try:
            from azure.identity import DefaultAzureCredential
            from azure.storage.blob import BlobServiceClient
        except ImportError as error:  # pragma: no cover - dependency bootstrapping path
            raise RuntimeError(
                "Azure import requires the azure-identity and azure-storage-blob packages."
            ) from error

        account_url = self.settings.azure_blob_service_url.strip()
        if account_url == "":
            account_url = f"https://{self.settings.azure_storage_account}.blob.core.windows.net"

        if self.settings.azure_auth_mode == "managedIdentity":
            credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
            return BlobServiceClient(account_url=account_url, credential=credential)

        if self.settings.azure_sas_token.strip() == "":
            raise ValueError(
                "PSCONNMON_AZURE_SAS_TOKEN is required when Azure auth mode is sasToken."
            )

        sas_token = self.settings.azure_sas_token.strip().lstrip("?")
        separator = "&" if "?" in account_url else "?"
        return BlobServiceClient(account_url=f"{account_url}{separator}{sas_token}")


class ImportManager:
    """Coordinate scheduled import runs and persist source status in DuckDB."""

    def __init__(self, repository: StorageRepository, settings: ServiceSettings) -> None:
        self.repository = repository
        self.settings = settings
        self._run_lock = threading.Lock()
        self._stop_event = asyncio.Event()

    def run_once(self) -> ImportStatus:
        """Run one import cycle across the configured source set."""

        with self._run_lock:
            for source in self._build_sources():
                self._import_source(source)

            return self.repository.get_import_status(self.settings.import_mode)

    async def run_forever(self) -> None:
        """Run import cycles until the app shuts down."""

        while not self._stop_event.is_set():
            await asyncio.to_thread(self.run_once)
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(), timeout=self.settings.import_interval_seconds
                )
            except TimeoutError:
                continue

    def stop(self) -> None:
        """Stop the periodic import loop."""

        self._stop_event.set()

    def _build_sources(self) -> list[BatchSource]:
        """Resolve the enabled import sources for this service instance."""

        if self.settings.import_mode == "disabled":
            return []

        if self.settings.import_mode == "local":
            return [LocalBatchSource(self.settings.import_local_path)]

        if self.settings.import_mode == "azure":
            return [AzureBlobBatchSource(self.settings)]

        if self.settings.import_mode == "hybrid":
            return [
                LocalBatchSource(self.settings.import_local_path),
                AzureBlobBatchSource(self.settings),
            ]

        raise ValueError(
            f"Unsupported import_mode '{self.settings.import_mode}'. "
            "Expected one of: 'disabled', 'local', 'azure', 'hybrid'."
        )

    def _import_source(self, source: BatchSource) -> None:
        """Import all discoverable batches for one source and persist status."""

        discovered = 0
        imported = 0
        skipped = 0
        failed = 0
        last_error: str | None = None
        last_source_identifier: str | None = None
        last_imported_batch_utc = None

        try:
            batches = source.iter_batches()
        except Exception as error:
            self.repository.record_import_source_status(
                source_type=source.source_type,
                discovered=0,
                imported=0,
                skipped=0,
                failed=1,
                backlog=1,
                last_error=str(error),
                last_source_identifier=None,
                mark_success=False,
                last_imported_batch_utc=None,
            )
            return

        for batch in batches:
            discovered += 1
            last_source_identifier = batch.source_identifier

            if self.repository.has_import_fingerprint(
                source_type=batch.source_type,
                source_identifier=batch.source_identifier,
                fingerprint=batch.fingerprint,
            ):
                skipped += 1
                continue

            try:
                events = self._parse_batch_content(batch.content)
                self.repository.ingest_import_batch(
                    source_type=batch.source_type,
                    source_identifier=batch.source_identifier,
                    fingerprint=batch.fingerprint,
                    events=events,
                )
                imported += 1
                last_imported_batch_utc = self.repository.get_last_imported_batch_time(
                    source_type=batch.source_type
                )
            except Exception as error:
                failed += 1
                last_error = str(error)

        self.repository.record_import_source_status(
            source_type=source.source_type,
            discovered=discovered,
            imported=imported,
            skipped=skipped,
            failed=failed,
            backlog=failed,
            last_error=last_error,
            last_source_identifier=last_source_identifier,
            mark_success=(failed == 0),
            last_imported_batch_utc=last_imported_batch_utc,
        )

    @staticmethod
    def _parse_batch_content(content: str) -> list[EventRecord]:
        """Parse JSONL content into validated event records."""

        events: list[EventRecord] = []
        for line_number, raw_line in enumerate(content.splitlines(), start=1):
            line = raw_line.strip()
            if line == "":
                continue

            try:
                payload = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"Invalid JSON on line {line_number}: {error.msg}") from error

            try:
                events.append(EventRecord.model_validate(payload))
            except Exception as error:
                raise ValueError(
                    f"Event validation failed on line {line_number}: {error}"
                ) from error

        if len(events) < 1:
            raise ValueError("Batch did not contain any event lines.")

        return events
