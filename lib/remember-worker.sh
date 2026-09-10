#!/usr/bin/env bash
set -uo pipefail
AKRO_ROOT="${AKRO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
[[ -r "$AKRO_ROOT/.env" ]] && source "$AKRO_ROOT/.env"
source "$AKRO_ROOT/config.sh"
source "$AKRO_ROOT/lib/common.sh"
source "$AKRO_ROOT/lib/ollama.sh"
source "$AKRO_ROOT/lib/projects.sh"
source "$AKRO_ROOT/lib/knowledge.sh"
source "$AKRO_ROOT/lib/brain.sh"

qdir="$AKRO_RUNTIME_DIR/remember"
lock="$qdir/worker.lock"
mkdir -p "$qdir/jobs"
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null || true' EXIT TERM INT
printf '%s\n' "$$" > "$qdir/worker.pid"

process_jobs() {
    local job="" rc=0
    for job in "$qdir/jobs"/*.json; do
        [[ -f "$job" ]] || continue
        if brain_learn_turn_job "$job"; then
            printf 'remembered:%s\n' "$(date '+%s')" > "$qdir/status"
        else
            rc=$?
            if (( rc == 2 )); then
                printf 'remembered:%s\n' "$(date '+%s')" > "$qdir/status"
            else
                printf 'failed:%s\n' "${BRAIN_ERROR:-unknown error}" > "$qdir/status"
            fi
        fi
        rm -f -- "$job"
    done
}

process_jobs
sleep 0.20
process_jobs
rm -f "$qdir/worker.pid"
