#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

printf 'Checking shell syntax...\n'
while IFS= read -r -d '' file; do bash -n "$file"; done < <(find "$ROOT" -name '*.sh' -print0)

printf 'Checking required repository files...\n'
for file in chat.sh config.sh README.md lib/skills.sh lib/brain.sh lib/knowledge.sh lib/projects.sh; do
  [[ -f "$ROOT/$file" ]] || { printf 'Missing: %s\n' "$file" >&2; exit 1; }
done

printf 'Checking skill manifests...\n'
count=0
for manifest in "$ROOT"/skills/*/skill.json; do
  [[ -f "$manifest" ]] || continue
  jq -e 'type=="object" and (.name|type=="string") and (.description|type=="string") and (.type=="prompt" or .type=="tool")' "$manifest" >/dev/null
  type="$(jq -r '.type' "$manifest")"
  if [[ "$type" == tool ]]; then
    entry="$(jq -r '.entrypoint // "run.sh"' "$manifest")"
    [[ -x "$(dirname "$manifest")/$entry" ]] || { printf 'Tool entrypoint is not executable: %s\n' "$manifest" >&2; exit 1; }
  fi
  count=$((count+1))
done
(( count > 0 )) || { printf 'No skills found.\n' >&2; exit 1; }

printf 'Checking skill folder names...\n'
for manifest in "$ROOT"/skills/*/skill.json; do
  folder="$(basename "$(dirname "$manifest")")"
  name="$(jq -r '.name' "$manifest")"
  [[ "$folder" == "$name" ]] || { printf 'Skill folder/name mismatch: %s != %s\n' "$folder" "$name" >&2; exit 1; }
done

printf 'Smoke test passed. %s skills detected.\n' "$count"
