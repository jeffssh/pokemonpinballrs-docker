#!/usr/bin/env bash
# Open the mGBA GUI inside the container, forwarded to XQuartz, so you can watch
# the reference ROM frame-by-frame and weigh in on diffs. Headless verification
# does NOT need this (see pokemon-pinball-table/tools/gba/) — this is purely the
# human review path.
#
# Usage:
#   ./emu.sh                  # opens pokepinballrs/baserom.gba in the arm64 container
#   ./emu.sh path/to.gba      # opens a specific ROM (container path)
#   EMU_SERVICE=claude-x86 ./emu.sh   # use the x86 container instead
#
# One-time Mac setup for X11 forwarding:
#   brew install --cask xquartz      # then log out / back in
#   open -a XQuartz; in XQuartz > Settings > Security: tick
#     "Allow connections from network clients"
#   xhost + 127.0.0.1
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SERVICE="${EMU_SERVICE:-claude}"
DISPLAY_FORWARD="${MGBA_DISPLAY:-host.docker.internal:0}"
ROM="${1:-/Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs/baserom.gba}"

PROFILE_ARGS=()
[ "$SERVICE" = "claude-x86" ] && PROFILE_ARGS=(--profile x86)

# Start the target service if it isn't running yet.
if [ -z "$(docker compose "${PROFILE_ARGS[@]}" ps -q --status running "$SERVICE" 2>/dev/null)" ]; then
    echo "Starting ${SERVICE}..."
    docker compose "${PROFILE_ARGS[@]}" up -d --build "$SERVICE"
fi

echo "Launching mgba-qt in '${SERVICE}' -> DISPLAY=${DISPLAY_FORWARD}"
echo "(If no window appears, see the XQuartz setup notes at the top of emu.sh.)"

# mGBA frame advance defaults to the Emulation menu / a hotkey; pause then step.
docker compose "${PROFILE_ARGS[@]}" exec \
    -e DISPLAY="$DISPLAY_FORWARD" \
    -e QT_X11_NO_MITSHM=1 \
    "$SERVICE" mgba-qt "$ROM"
