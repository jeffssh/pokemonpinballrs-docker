#!/usr/bin/env bash
# SessionStart hook: ingest collaborators' work into the session, for BOTH
# rw working repos (pokemon-pinball-table = primary, pokepinballrs = ref).
#
# Contract: NEVER block the session, NEVER destroy uncommitted work.
# Read-only anonymous HTTPS (the sandbox has no SSH key by design, so it
# physically cannot push). stdout here is injected into the model's
# context, so it doubles as the "here's what humans did" briefing.
set -uo pipefail

BASE=/Users/jeff/Documents/github/pokemonpinballrs-docker

sync_repo() {
    repo="$1" url="$2" name="$3"
    cd "$repo" 2>/dev/null || { echo "[git-sync:$name] no repo at $repo"; return; }
    br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return
    before=$(git rev-parse HEAD 2>/dev/null)

    # Anonymous mirror of the SSH origin. We never touch remote config, so
    # host-side pushes keep using SSH; the container only ever reads.
    if ! git fetch --quiet "$url" "+${br}:refs/remotes/origin/${br}" 2>/dev/null; then
        echo "[git-sync:$name] no anonymous access (private repo or offline); ${br} unchanged in-session. Private repos sync host-side at ./start.sh."
        return
    fi

    remote=$(git rev-parse "origin/${br}" 2>/dev/null)
    if [ "$before" = "$remote" ]; then
        echo "[git-sync:$name] ${br} in sync with collaborators (${before:0:9})."
        return
    fi

    incoming=$(git rev-list --count "${before}..${remote}" 2>/dev/null || echo "?")
    log=$(git log --oneline --no-decorate "${before}..${remote}" 2>/dev/null | sed 's/^/    /')

    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "[git-sync:$name] ${incoming} new human commit(s) on ${br}, tree DIRTY."
        echo "[git-sync:$name] Not merging — protecting your work. Commit, then: git merge --ff-only origin/${br}"
        echo "$log"
    elif git merge --ff-only "origin/${br}" >/dev/null 2>&1; then
        echo "[git-sync:$name] Fast-forwarded ${br} +${incoming} human commit(s) — review before building on them:"
        echo "$log"
    else
        echo "[git-sync:$name] ${incoming} new human commit(s) on ${br} but history diverged."
        echo "[git-sync:$name] Not auto-merging. Reconcile: git rebase origin/${br} (resolve conflicts, do not discard)."
        echo "$log"
    fi
}

sync_repo "$BASE/pokemon-pinball-table" "https://github.com/jeffssh/pokemon-pinball-table.git" "table"
sync_repo "$BASE/pokepinballrs"         "https://github.com/jeffssh/pokepinballrs.git"         "rs"
exit 0
