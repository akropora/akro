#!/usr/bin/env bash
set -uo pipefail

AKRO_ROOT="${AKRO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd -P)}"

prompt="$(cat)"

if [[ -z "$(printf '%s' "$prompt" | tr -d '[:space:]')" ]]; then
    printf 'Give /work a problem or task to complete.\n' >&2
    exit 1
fi

framework_file="$(cd "$(dirname "$0")" && pwd -P)/framework.md"

if [[ ! -r "$framework_file" ]]; then
    printf 'Work framework is missing: %s\n' "$framework_file" >&2
    exit 1
fi

framework="$(cat "$framework_file")"

transformed="$framework

---

# Current Work Request

The following material is the task to complete.

It may already contain context added by another Akro skill such as /search or /document. Treat that supplied context according to its own source boundaries and instructions.

Do not merely restate this request. Apply the complete WORK framework above and carry the task through to the strongest finished result possible.

--- BEGIN WORK REQUEST ---
$prompt
--- END WORK REQUEST ---"

jq -n \
    --arg prompt "$transformed" \
    --arg notice "Work mode: deep planning, execution, and verification enabled." \
    '{
        prompt: $prompt,
        notice: $notice
    }'
