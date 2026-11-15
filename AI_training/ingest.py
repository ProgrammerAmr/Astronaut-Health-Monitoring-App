"""
Index NASA documents (.md / .txt) into ChromaDB. Run this OFFLINE, not on every app start.

    python ingest.py                 # index new/changed files, prune deleted ones
    python ingest.py --rebuild       # wipe the index and rebuild (needed after changing the embedding model)
    python ingest.py --docs-dir ./some/folder
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from nasa_claude import KnowledgeBase, Settings, setup_logging


def main() -> int:
    parser = argparse.ArgumentParser(description="Index NASA docs into ChromaDB")
    parser.add_argument("--rebuild", action="store_true", help="delete the existing index first")
    parser.add_argument("--docs-dir", type=Path, default=None, help="override NASA_DOCS_DIR")
    args = parser.parse_args()

    setup_logging()
    settings = Settings.from_env()
    if args.docs_dir:
        settings.docs_dir = args.docs_dir

    stats = KnowledgeBase(settings).ingest(rebuild=args.rebuild)
    print(json.dumps(stats, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
