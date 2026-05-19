#!/usr/bin/env bash
# SessionStart hook: ingest collaborators' work into the session.
#
# Contract: NEVER block the session, NEVER destroy uncommitted work.
# Read-only anonymous HTTPS (the sandbox has no SSH key by design, so it
# physically cannot push). stdout here is injected into the model's
# context, so it doubles as the "here's what humans did" briefing.
set -uo pipefail

REPO=/Users/jeff/Documents/github/pokemonpinballrs-docker/pokepinballrs
cd "$REPO" 2>/dev/null || { echo "[git-sync] no repo at $REPO"; exit 0; }

BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
# Anonymous mirror of the SSH origin. We never touch remote config, so
# host-side pushes keep using SSH; the container only ever reads.
FETCH_URL="https://github.com/jeffssh/pokepinballrs.git"

before=$(git rev-parse HEAD 2>/dev/null)

if ! git fetch --quiet "$FETCH_URL" "+${BR}:refs/remotes/origin/${BR}" 2>/dev/null; then
    echo "[git-sync] fetch failed (offline, or fork is private — no anon HTTPS). Working tree unchanged on ${BR}."
    exit 0
fi

remote=$(git rev-parse "origin/${BR}" 2>/dev/null)
if [ "$before" = "$remote" ]; then
    echo "[git-sync] ${BR} already in sync with collaborators (${before:0:9})."
    exit 0
fi

incoming=$(git rev-list --count "${before}..${remote}" 2>/dev/null || echo "?")
log=$(git log --oneline --no-decorate "${before}..${remote}" 2>/dev/null | sed 's/^/  /')

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "[git-sync] ${incoming} new human commit(s) on ${BR}, but the working tree is DIRTY."
    echo "[git-sync] Not merging — protecting in-progress work. Commit, then: git merge --ff-only origin/${BR}"
    echo "$log"
elif git merge --ff-only "origin/${BR}" >/dev/null 2>&1; then
    echo "[git-sync] Fast-forwarded ${BR} +${incoming} human commit(s) — review before building on them:"
    echo "$log"
else
    echo "[git-sync] ${incoming} new human commit(s) on ${BR} but history diverged (local commits exist)."
    echo "[git-sync] Not auto-merging. Reconcile with: git rebase origin/${BR}  (resolve conflicts, do not discard)."
    echo "$log"
fi
exit 0
