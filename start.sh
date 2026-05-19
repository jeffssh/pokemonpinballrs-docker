#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

HOST_CLAUDE="${HOME}/.claude"
SLUG="-Users-jeff-Documents-github-pokemonpinballrs-docker-pokepinballrs"

# pokepinballrs + pokemon-pinball-table are git submodules of this repo.
# Init them if this is a fresh clone (uses YOUR ssh creds on the host).
if [ ! -e pokepinballrs/.git ] || [ ! -e pokemon-pinball-table/.git ]; then
    echo "Initializing submodules..."
    git submodule update --init --recursive
fi

# Host-side sync before launch: uses YOUR ssh creds (the container has
# none, by design). Fast-forward only — never clobbers local/agent work.
# If history diverged, the in-container SessionStart hook surfaces it.
echo "Syncing pokepinballrs with collaborators..."
git -C pokepinballrs pull --ff-only 2>/dev/null \
    && echo "  up to date / fast-forwarded." \
    || echo "  skipped ff-only pull (diverged or offline) — in-container hook will report."

# Container-local state + trusted config dirs.
mkdir -p state/claude-home state/discord-export state/secrets claude-config/agents claude-config/hooks

# The ro .claude guard mount needs a real host dir owned by jeff.
mkdir -p pokepinballrs/.claude

# Pre-create host session mountpoints so Docker doesn't make them
# root-owned. These are the only host ~/.claude paths shared in.
mkdir -p "${HOST_CLAUDE}/projects/${SLUG}" "${HOST_CLAUDE}/tasks" "${HOST_CLAUDE}/file-history"
[ -f "${HOST_CLAUDE}/history.jsonl" ] || touch "${HOST_CLAUDE}/history.jsonl"

echo "Building and starting container..."
docker compose up -d --build
echo "Container ready."

# One-time agbcc install into the (runtime-mounted) project. The compile
# already happened in the image; this is just the file copy install.sh does.
if [ ! -x pokepinballrs/tools/agbcc/bin/agbcc ]; then
    echo "Installing agbcc into the project..."
    docker compose exec -T claude bash -lc \
        'cd /opt/agbcc && ./install.sh /Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs'
    echo "agbcc installed (persists on host at pokepinballrs/tools/agbcc)."
fi

# First-time login: OAuth token persists in state/claude-home/.credentials.json
if [ ! -f "state/claude-home/.credentials.json" ]; then
    echo ""
    echo "No auth found. Running 'claude login' — follow the URL in your browser."
    echo ""
    docker compose exec claude claude login
    echo ""
    echo "Login complete. Token persists in state/claude-home/ (not on host ~/.claude)."
fi

if [ ! -f pokepinballrs/baserom.gba ]; then
    echo ""
    echo "NOTE: pokepinballrs/baserom.gba is missing."
    echo "      Drop your own cartridge dump there to enable 'make compare'."
fi
