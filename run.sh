#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Start (idempotent) if not already running.
if ! docker compose ps --status running 2>/dev/null | grep -q pokepin-claude; then
    ./start.sh
fi

# Launch in pokemon-pinball-table (compose working_dir) as the primary
# git-rooted project. --add-dir grants the agent the pokepinballrs decomp
# (the other rw working repo) as a second workspace root, so it can read
# and edit both without the primary's session slug shifting.
#
# --dangerously-skip-permissions is the sandbox YOLO flag — safe here
# because blast radius is contained to the mounted submodules + shared
# session dirs (see claude-config/CLAUDE.md for the threat model).
# docker compose exec allocates a TTY by default. No -p so output
# streams live; a positional arg seeds the first message.
ADD_DIR=/Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs
if [ $# -gt 0 ]; then
    docker compose exec claude claude --dangerously-skip-permissions --add-dir "$ADD_DIR" "$*"
else
    docker compose exec claude claude --dangerously-skip-permissions --add-dir "$ADD_DIR"
fi
