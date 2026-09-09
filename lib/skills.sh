#!/usr/bin/env bash

SKILL_PROMPT=""
SKILL_USED=""
SKILL_NOTICE=""
SKILL_ERROR=""
SKILL_VERBOSE=0

skill_add_used() {
    local name="$1"
    if [[ -z "$SKILL_USED" ]]; then SKILL_USED="$name"; else SKILL_USED="$SKILL_USED $name"; fi
}

skill_manifest() {
    local name="$1"
    local path="$AKRO_SKILLS_DIR/$name/skill.json"
    [[ -f "$path" ]] || return 1
    printf '%s' "$path"
}

skill_exists() { skill_manifest "$1" >/dev/null 2>&1; }

skill_validate_manifest() {
    jq -e 'type=="object" and (.name|type=="string") and (.type=="prompt" or .type=="tool") and (.description|type=="string")' "$1" >/dev/null 2>&1
}

skill_list() {
    local manifest="" name="" syntax="" description="" type=""
    for manifest in "$AKRO_SKILLS_DIR"/*/skill.json; do
        [[ -f "$manifest" ]] || continue
        skill_validate_manifest "$manifest" || continue
        name="$(jq -r '.name' "$manifest")"; syntax="$(jq -r '.syntax // ("/"+.name)' "$manifest")"; description="$(jq -r '.description' "$manifest")"; type="$(jq -r '.type' "$manifest")"
        printf '  %-14s %-7s %s\n' "$syntax" "$type" "$description"
    done | sort
}

skill_parse_tail() {
    local text="$1" matched_name="" matched_arg="" prefix="" name="" arg=""
    SKILL_PARSE_NAME=""; SKILL_PARSE_ARG=""; SKILL_PARSE_PREFIX="$text"

    # Generic skill grammar: /name or /name [argument] at the end of the request.
    if [[ "$text" =~ (.*)[[:space:]]/([A-Za-z0-9_-]+)[[:space:]]+\[([^][]*)\][[:space:]]*$ ]]; then
        prefix="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; arg="${BASH_REMATCH[3]}"
    elif [[ "$text" =~ (.*)[[:space:]]/([A-Za-z0-9_-]+)[[:space:]]*$ ]]; then
        prefix="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"; arg=""
    elif [[ "$text" =~ ^/([A-Za-z0-9_-]+)[[:space:]]+\[([^][]*)\][[:space:]]*$ ]]; then
        prefix=""; name="${BASH_REMATCH[1]}"; arg="${BASH_REMATCH[2]}"
    elif [[ "$text" =~ ^/([A-Za-z0-9_-]+)[[:space:]]*$ ]]; then
        prefix=""; name="${BASH_REMATCH[1]}"; arg=""
    else
        return 1
    fi

    skill_exists "$name" || return 1
    SKILL_PARSE_NAME="$name"; SKILL_PARSE_ARG="$arg"; SKILL_PARSE_PREFIX="$(akro_trim "$prefix")"
}

skill_run_tool() {
    local name="$1" arg="$2" prompt="$3" manifest="" entry="" activity="" input="" output="" err="" pid=0 rc=0 result="" notice=""
    manifest="$(skill_manifest "$name")" || return 1
    entry="$(jq -r '.entrypoint // "run.sh"' "$manifest")"
    entry="$AKRO_SKILLS_DIR/$name/$entry"
    [[ -x "$entry" ]] || { SKILL_ERROR="Tool skill /$name has no executable entrypoint: $entry"; return 1; }
    activity="$(jq -r '.activity // (.name + " working")' "$manifest")"
    input="$(mktemp "$AKRO_RUNTIME_DIR/skill-in.XXXXXX")"; output="$(mktemp "$AKRO_RUNTIME_DIR/skill-out.XXXXXX")"; err="$(mktemp "$AKRO_RUNTIME_DIR/skill-err.XXXXXX")"
    printf '%s' "$prompt" > "$input"
    AKRO_ROOT="$AKRO_ROOT" AKRO_DATA_DIR="$AKRO_DATA_DIR" AKRO_GLOBAL_DIR="$AKRO_GLOBAL_DIR" AKRO_PROJECTS_DIR="$AKRO_PROJECTS_DIR" AKRO_STATE_FILE="$AKRO_STATE_FILE" AKRO_RUNTIME_DIR="$AKRO_RUNTIME_DIR" CURRENT_PROJECT_DIR="$CURRENT_PROJECT_DIR" CURRENT_PROJECT_SLUG="$CURRENT_PROJECT_SLUG" CURRENT_PROJECT_NAME="$CURRENT_PROJECT_NAME" AKRO_SKILL_ARG="$arg" TAVILY_API_KEY="$TAVILY_API_KEY" TAVILY_API_URL="$TAVILY_API_URL" TAVILY_MAX_RESULTS="$TAVILY_MAX_RESULTS" DOCUMENT_MAX_BYTES="$DOCUMENT_MAX_BYTES" DOCUMENT_INLINE_BYTES="$DOCUMENT_INLINE_BYTES" "$entry" < "$input" > "$output" 2> "$err" &
    pid=$!
    if ui_activity_wait "$pid" "$activity"; then rc=0; else rc=$?; fi
    if (( rc != 0 )); then SKILL_ERROR="$(cat "$err")"; [[ -n "$SKILL_ERROR" ]] || SKILL_ERROR="Skill /$name failed."; rm -f "$input" "$output" "$err"; return 1; fi
    result="$(cat "$output")"
    if ! jq -e 'type=="object" and (.prompt|type=="string")' <<< "$result" >/dev/null 2>&1; then SKILL_ERROR="Skill /$name returned invalid JSON."; rm -f "$input" "$output" "$err"; return 1; fi
    SKILL_PROMPT="$(jq -r '.prompt' <<< "$result")"
    notice="$(jq -r '.notice // empty' <<< "$result")"; [[ -z "$notice" ]] || SKILL_NOTICE+="${SKILL_NOTICE:+$'\n'}$notice"
    rm -f "$input" "$output" "$err"
}

process_skills() {
    local original="$1" remaining="$1" name="" arg="" manifest="" type="" instruction="" instructions=""
    local -a names=() args=()
    SKILL_PROMPT="$original"; SKILL_USED=""; SKILL_NOTICE=""; SKILL_ERROR=""; SKILL_VERBOSE=0

    # Parse suffix skills from right to left, but execute tool skills in the
    # user's written order. Prompt modifiers are applied after tools so they
    # never pollute a search query or document path operation.
    while skill_parse_tail "$remaining"; do
        name="$SKILL_PARSE_NAME"; arg="$SKILL_PARSE_ARG"; remaining="$SKILL_PARSE_PREFIX"
        names+=("$name"); args+=("$arg")
    done

    remaining="$(akro_trim "$remaining")"
    if [[ "$remaining" =~ (^|[[:space:]])/([A-Za-z0-9_-]+)[[:space:]]*$ ]]; then
        SKILL_ERROR="Unknown skill: /${BASH_REMATCH[2]}"
        return 1
    fi
    SKILL_PROMPT="$remaining"

    local i=0
    for ((i=${#names[@]}-1; i>=0; i--)); do
        name="${names[$i]}"; arg="${args[$i]}"; manifest="$(skill_manifest "$name")"; type="$(jq -r '.type' "$manifest")"
        skill_add_used "/$name"
        if [[ "$type" == prompt ]]; then
            [[ -z "$arg" ]] || { SKILL_ERROR="Prompt skill /$name does not accept an argument."; return 1; }
            instruction="$(jq -r '.instruction // empty' "$manifest")"
            [[ -n "$instruction" ]] || { SKILL_ERROR="Prompt skill /$name has no instruction."; return 1; }
            instructions+="${instructions:+$'\n\n'}$instruction"
        else
            skill_run_tool "$name" "$arg" "$SKILL_PROMPT" || return 1
        fi
    done

    if [[ -n "$instructions" ]]; then
        SKILL_PROMPT="$instructions${SKILL_PROMPT:+$'\n\n'$SKILL_PROMPT}"
    fi
    return 0
}
