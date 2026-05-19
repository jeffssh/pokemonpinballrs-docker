#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Start (idempotent) if not already running.
if ! docker compose ps --status running 2>/dev/null | grep -q pokepin-claude; then
    ./start.sh
fi

# --dangerously-skip-permissions is the sandbox YOLO flag — safe here
# because blast radius is contained to the mounted project + shared
# session dirs (see claude-config/CLAUDE.md for the threat model).
# docker compose exec allocates a TTY by default. No -p so output
# streams live; a positional arg seeds the first message.
if [ $# -gt 0 ]; then
    docker compose exec claude claude --dangerously-skip-permissions "$*"
else
    docker compose exec claude claude --dangerously-skip-permissions
fi
