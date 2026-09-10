#!/usr/bin/env bash

MESSAGES_JSON='[]'
CURRENT_CHAT_FILE=""
CURRENT_CHAT_NAME=""
CURRENT_CHAT_ID=""
CURRENT_CHAT_CREATED=""
LAST_PROMPT_TOKENS=0
LAST_REPLY_TOKENS=0

chat_id() { printf 'chat-%s-%s-%s' "$(date '+%Y%m%d%H%M%S')" "$$" "$RANDOM"; }

chat_unique_path() {
    local title="$1" slug="" path="" n=2
    slug="$(akro_slug "$title")"; path="$CURRENT_PROJECT_DIR/chats/$slug.json"
    while [[ -e "$path" ]]; do path="$CURRENT_PROJECT_DIR/chats/$slug-$n.json"; n=$((n+1)); done
    printf '%s' "$path"
}

chat_title_fallback() {
    local text="$1" clean=""
    clean="$(printf '%s' "$text" | tr '\n\r\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' | cut -c 1-58)"
    [[ -n "$clean" ]] || clean="New Chat"
    printf '%s' "$clean"
}

chat_generate_title() {
    local first="$1" prompt="" title=""
    local schema='{"type":"object","properties":{"title":{"type":"string","minLength":1,"maxLength":72}},"required":["title"],"additionalProperties":false}'
    prompt="Create a short useful title for this conversation. Return the actual title in the title field. Aim for 3 to 7 words. Capture the subject or goal. No punctuation at the end. Do not invent details.\n\nFIRST USER MESSAGE:\n$first"
    if ollama_model_exists "$NEURON_MODEL" && ollama_call_json "$NEURON_MODEL" "$prompt" 80 4096 "$schema"; then
        title="$(jq -r '.title // empty' <<< "$OLLAMA_RESULT" | tr '\n\r\t' '   ' | cut -c 1-72)"
    fi
    [[ -n "$title" && "$title" != *'{'* ]] || title="$(chat_title_fallback "$first")"
    printf '%s' "$title"
}

chat_write() {
    local dest="$1" name="$2"
    [[ -n "$CURRENT_CHAT_ID" ]] || CURRENT_CHAT_ID="$(chat_id)"
    [[ -n "$CURRENT_CHAT_CREATED" ]] || CURRENT_CHAT_CREATED="$(akro_timestamp)"
    jq -n --arg id "$CURRENT_CHAT_ID" --arg name "$name" --arg model "$BASE_MODEL" --arg project "$CURRENT_PROJECT_SLUG" --arg created "$CURRENT_CHAT_CREATED" --arg updated "$(akro_timestamp)" --argjson messages "$MESSAGES_JSON" '{version:2,id:$id,name:$name,model:$model,project:$project,created:$created,updated:$updated,messages:$messages}' | akro_atomic_write "$dest"
}

chat_autosave() { [[ -z "$CURRENT_CHAT_FILE" ]] || chat_write "$CURRENT_CHAT_FILE" "$CURRENT_CHAT_NAME"; }

chat_start_from_prompt() {
    local first="$1" title_file="" pid=0
    [[ -z "$CURRENT_CHAT_FILE" ]] || return 0
    title_file="$(mktemp "$AKRO_RUNTIME_DIR/title.XXXXXX")"
    (chat_generate_title "$first" > "$title_file") & pid=$!
    ui_activity_wait "$pid" "naming chat" || true
    CURRENT_CHAT_NAME="$(cat "$title_file")"; rm -f "$title_file"
    [[ -n "$CURRENT_CHAT_NAME" ]] || CURRENT_CHAT_NAME="$(chat_title_fallback "$first")"
    CURRENT_CHAT_ID="$(chat_id)"; CURRENT_CHAT_CREATED="$(akro_timestamp)"; CURRENT_CHAT_FILE="$(chat_unique_path "$CURRENT_CHAT_NAME")"
    chat_write "$CURRENT_CHAT_FILE" "$CURRENT_CHAT_NAME"
    printf '%b[chat: %s]%b\n\n' "$GREEN" "$CURRENT_CHAT_NAME" "$RESET"
}

chat_new() {
    MESSAGES_JSON='[]'; CURRENT_CHAT_FILE=""; CURRENT_CHAT_NAME=""; CURRENT_CHAT_ID=""; CURRENT_CHAT_CREATED=""; LAST_PROMPT_TOKENS=0; LAST_REPLY_TOKENS=0
}

chat_append_user() { MESSAGES_JSON="$(jq -c --arg s "$1" '. + [{role:"user",content:$s}]' <<< "$MESSAGES_JSON")"; }
chat_append_assistant() { MESSAGES_JSON="$(jq -c --arg s "$1" --arg model "$2" '. + [{role:"assistant",content:$s,model:$model}]' <<< "$MESSAGES_JSON")"; }

chat_context_window() {
    local messages="$1" max_chars="${CHAT_HISTORY_MAX_CHARS:-24000}" max_messages="${CHAT_HISTORY_MAX_MESSAGES:-24}"
    jq -c --argjson chars "$max_chars" --argjson max "$max_messages" '
      (if length > $max then .[(length-$max):] else . end) as $r
      | reduce ($r|reverse[]) as $m ({items:[],chars:0,stop:false}; if .stop then . else (($m.content//"")|length) as $n | if ((.chars+$n)<=$chars) or ((.items|length)==0) then .items += [$m] | .chars += $n else .stop=true end end)
      | .items | reverse' <<< "$messages"
}

chat_load() {
    local file="$1" saved_model=""
    jq -e 'type=="object" and (.messages|type=="array")' "$file" >/dev/null 2>&1 || return 1
    MESSAGES_JSON="$(jq -c '.messages' "$file")"; CURRENT_CHAT_FILE="$file"; CURRENT_CHAT_NAME="$(jq -r '.name // empty' "$file")"
    [[ -n "$CURRENT_CHAT_NAME" ]] || CURRENT_CHAT_NAME="$(basename "$file" .json)"
    CURRENT_CHAT_ID="$(jq -r '.id // empty' "$file")"; [[ -n "$CURRENT_CHAT_ID" ]] || CURRENT_CHAT_ID="$(chat_id)"
    CURRENT_CHAT_CREATED="$(jq -r '.created // empty' "$file")"; [[ -n "$CURRENT_CHAT_CREATED" ]] || CURRENT_CHAT_CREATED="$(akro_timestamp)"
    saved_model="$(jq -r '.model // empty' "$file")"; [[ -z "$saved_model" ]] || { ollama_model_exists "$saved_model" && BASE_MODEL="$saved_model"; }
    LAST_PROMPT_TOKENS=0; LAST_REPLY_TOKENS=0
}
