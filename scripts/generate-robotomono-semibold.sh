#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
uv sync
uv run python generate-robotomono-semibold.py "$@"
