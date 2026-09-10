#!/usr/bin/env bash
set -uo pipefail
prompt="$(cat)"
[[ -n "$(printf '%s' "$prompt" | tr -d '[:space:]')" ]] || { printf 'Give /work a problem or task to complete.\n' >&2; exit 1; }
framework="$(cat "$(dirname "$0")/framework.md")"
transformed="$framework

---

# Current Work Request

$prompt"
jq -n --arg prompt "$transformed" --arg notice "Work framework applied." '{prompt:$prompt,notice:$notice}'
