#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Bulk-dumps the RE community server to static JSON the agent reads as
# UNTRUSTED reference data. Run from the HOST. Deliberately NOT a compose
# service and NOT wired to the claude container: the Discord token never
# touches the agent's environment, and there is no live Discord tool —
# so an injected agent has no way to post, DM, or drive the Discord API.
#
# DiscordChatExporter (Tyrrrz) — mature, official Docker image, supports
# the throwaway user account's token.
#
# Setup (one time):
#   1. Create a throwaway Discord account, join the RE server.
#   2. Put its user token in:        state/secrets/discord_token
#   3. Put the server (guild) ID in: state/secrets/discord_guild
#      (Discord: User Settings > Advanced > Developer Mode, then
#       right-click the server > Copy Server ID.)
#
# Re-run this whenever you want fresh context. Output: state/discord-export/

TOKEN_FILE="state/secrets/discord_token"
GUILD_FILE="state/secrets/discord_guild"

for f in "$TOKEN_FILE" "$GUILD_FILE"; do
    if [ ! -s "$f" ]; then
        echo "ERROR: missing/empty $f — see header of this script for setup."
        exit 1
    fi
done

TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
GUILD="$(tr -d '[:space:]' < "$GUILD_FILE")"

mkdir -p state/discord-export

# -e DISCORD_TOKEN keeps the token out of argv/ps and image history.
# No --media: we only want text, never attacker-supplied attachments.
docker run --rm \
    -e DISCORD_TOKEN="$TOKEN" \
    -v "$(pwd)/state/discord-export:/out" \
    tyrrrz/discordchatexporter:stable \
    exportguild -g "$GUILD" -f Json -o "/out/%C-%c.json"

echo ""
echo "Export complete -> state/discord-export/ (mounted READ-ONLY into the container)."
echo "The agent consults it ONLY via the 'discord-context' quarantine subagent."
