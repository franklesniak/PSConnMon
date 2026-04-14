"""CLI entrypoint for local service execution."""

from __future__ import annotations

import uvicorn


def main() -> None:
    """Run the PSConnMon reporting service."""

    uvicorn.run(
        "psconnmon_service.app:create_app",
        host="0.0.0.0",
        port=8080,
        reload=False,
        factory=True,
    )


if __name__ == "__main__":
    main()
