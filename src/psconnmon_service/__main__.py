"""CLI entrypoint for local service execution."""

from __future__ import annotations

import uvicorn


def main() -> None:
    """Run the PSConnMon reporting service."""

    uvicorn.run("psconnmon_service.app:app", host="0.0.0.0", port=8080, reload=False)


if __name__ == "__main__":
    main()
