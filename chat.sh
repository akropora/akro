#!/usr/bin/env bash
set -uo pipefail

AKRO_ROOT="${AKRO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
[[ -r "$AKRO_ROOT/.env" ]] && source "$AKRO_ROOT/.env"
source "$AKRO_ROOT/config.sh"
source "$AKRO_ROOT/lib/common.sh"
source "$AKRO_ROOT/lib/ui.sh"
source "$AKRO_ROOT/lib/ollama.sh"
source "$AKRO_ROOT/lib/projects.sh"
source "$AKRO_ROOT/lib/chats.sh"
source "$AKRO_ROOT/lib/knowledge.sh"
source "$AKRO_ROOT/lib/brain.sh"
source "$AKRO_ROOT/lib/skills.sh"
source "$AKRO_ROOT/lib/commands.sh"

BASE_MODEL=""
USER_INPUT=""

trap ui_cleanup EXIT TERM
trap 'printf "\n%bUse /quit to exit.%b\n\n" "$GRAY" "$RESET"' INT

session_title() { [[ -n "$CURRENT_CHAT_NAME" ]] && printf '%s' "$CURRENT_CHAT_NAME" || printf 'New Chat'; }

ui_header() {
    printf '\033[2J\033[H'
    printf '%b%s%b\n' "$WHITE" "$UI_TITLE" "$RESET"
    printf '%bmodel:%b   %s\n' "$GRAY" "$RESET" "${BASE_MODEL%:latest}"
    printf '%bproject:%b %s\n' "$GRAY" "$RESET" "$CURRENT_PROJECT_NAME"
    printf '%bchat:%b    %s\n' "$GRAY" "$RESET" "$(session_title)"
    printf '%bcontext:%b ' "$GRAY" "$RESET"; ui_context_bar "$LAST_PROMPT_TOKENS"; printf '\n\n'
}

ui_render_history() {
    local count=0 i=0 role="" content="" model=""
    count="$(jq 'length' <<< "$MESSAGES_JSON")"
    for ((i=0;i<count;i++)); do
        role="$(jq -r ".[$i].role // empty" <<< "$MESSAGES_JSON")"; content="$(jq -r ".[$i].content // empty" <<< "$MESSAGES_JSON")"; model="$(jq -r ".[$i].model // empty" <<< "$MESSAGES_JSON")"
        if [[ "$role" == user ]]; then printf '%b you > %b%s\n\n' "$BLUE" "$RESET" "$content"; else
            [[ -n "$model" ]] || model="$BASE_MODEL"; printf '%b %s > %b\n' "$PURPLE" "${model%:latest}" "$RESET"; ui_render_markdown "$content"; printf '\n'
        fi
    done
}

ui_redraw() { ui_header; ui_render_history; }

read_prompt() {
    local input="" prompt=""
    prompt="$(printf '\001%b\002 you > \001%b\002' "$BLUE" "$RESET")"
    if ! IFS= read -e -r -p "$prompt" input; then printf '\n'; return 1; fi
    if [[ "$input" == /* ]]; then tput cuu1 2>/dev/null || true; tput el 2>/dev/null || true; printf '%b you > %s%b\n' "$ORANGE" "$input" "$RESET"; fi
    USER_INPUT="$input"
}

read_multiline() {
    local line="" text=""
    printf '%b... > multiline mode, finish with """ on its own line%b\n' "$GRAY" "$RESET"
    while true; do IFS= read -r -p "... > " line || break; [[ "$line" == '"""' ]] && break; text+="${text:+$'\n'}$line"; done
    USER_INPUT="$text"
}

project_instructions() {
    local file="$CURRENT_PROJECT_DIR/instructions.md"
    [[ -s "$file" ]] || return 0
    printf 'PROJECT INSTRUCTIONS\nThese are user-authored instructions for the active project.\n\n'
    cat "$file"
}

auto_learn_current_chat() {
    [[ "${AKRO_AUTO_LEARN:-1}" == "1" && -n "$CURRENT_CHAT_FILE" ]] || return 0
    local out="$(mktemp "$AKRO_RUNTIME_DIR/autolearn.XXXXXX")" err="$(mktemp "$AKRO_RUNTIME_DIR/autolearn-err.XXXXXX")" pid=0 rc=0
    (brain_learn_source "$CURRENT_PROJECT_DIR" chat "$CURRENT_CHAT_FILE" > "$out" 2> "$err") & pid=$!
    if ui_activity_wait "$pid" "remembering"; then rc=0; else rc=$?; fi
    if [[ "$rc" != 0 && "$rc" != 2 ]]; then ui_notice "Brain note skipped: $(cat "$err")" "$YELLOW"; fi
    rm -f "$out" "$err"
}

run_chat_turn() {
    local original="$1" prepared="$2" memory="" knowledge="" instructions="" request="" history="" request_messages="" response_file="" error_file="" assistant="" api_error=""
    chat_start_from_prompt "$original" || return 1
    memory="$(brain_context "$original" 2>/dev/null || true)"
    knowledge="$(knowledge_context "$original" 2>/dev/null || true)"
    memory="$(printf '%s' "$memory" | head -c "$BRAIN_CONTEXT_MAX_CHARS")"
    knowledge="$(printf '%s' "$knowledge" | head -c "$KNOWLEDGE_CONTEXT_MAX_CHARS")"
    instructions="$(project_instructions 2>/dev/null || true)"
    request="$prepared"
    if [[ -n "$instructions$memory$knowledge" ]]; then
        request="${instructions:+$instructions$'\n\n'}${memory:+$memory$'\n\n'}${knowledge:+$knowledge$'\n\n'}CURRENT USER REQUEST:\n$prepared"
    fi

    history="$MESSAGES_JSON"
    chat_append_user "$original"; chat_autosave
    request_messages="$(chat_context_window "$history" | jq -c --arg content "$request" '[.[]|{role:.role,content:.content}] + [{role:"user",content:$content}]')"
    jq -n --arg model "$BASE_MODEL" --arg project "$CURRENT_PROJECT_NAME" --arg skills "${SKILL_USED:-}" --argjson messages "$request_messages" '{model:$model,project:$project,skills:$skills,messages:$messages}' | akro_atomic_write "$AKRO_RUNTIME_DIR/last-prompt.json"

    response_file="$(mktemp "$AKRO_RUNTIME_DIR/chat-response.XXXXXX")"; error_file="$(mktemp "$AKRO_RUNTIME_DIR/chat-error.XXXXXX")"
    ollama_stream_chat "$BASE_MODEL" "$request_messages" "$response_file" "$error_file" || true
    api_error="$(jq -r 'select(.error != null) | .error' "$response_file" 2>/dev/null | head -n1 || true)"
    if [[ -n "$api_error" ]]; then ui_notice "Ollama request failed: $api_error" "$RED"; rm -f "$response_file" "$error_file"; return 1; fi
    assistant="$(jq -rs '[.[] | .message.content // empty] | join("")' "$response_file" 2>/dev/null || true)"
    if [[ -z "$assistant" ]]; then
        local err="$(cat "$error_file")"; [[ -n "$err" ]] || err='Ollama returned an empty response.'; ui_notice "$err" "$RED"; rm -f "$response_file" "$error_file"; return 1
    fi
    LAST_PROMPT_TOKENS="$(jq -rs '[.[]|.prompt_eval_count//empty]|last//0' "$response_file" 2>/dev/null || printf 0)"
    LAST_REPLY_TOKENS="$(jq -rs '[.[]|.eval_count//empty]|last//0' "$response_file" 2>/dev/null || printf 0)"
    chat_append_assistant "$assistant" "$BASE_MODEL"; chat_autosave
    printf '%bcontext:%b ' "$GRAY" "$RESET"; ui_context_bar "$LAST_PROMPT_TOKENS"; printf '   %breply:%b %s\n\n' "$GRAY" "$RESET" "$(ui_format_count "$LAST_REPLY_TOKENS")"
    rm -f "$response_file" "$error_file"
    auto_learn_current_chat
}

main_loop() {
    local input="" rc=0
    while true; do
        USER_INPUT=""; read_prompt || continue; input="$USER_INPUT"; [[ -n "$input" ]] || continue
        if [[ "$input" == '"""' ]]; then read_multiline; input="$USER_INPUT"; [[ -n "$input" ]] || continue; fi
        if handle_user_command "$input"; then continue; else rc=$?; (( rc != 10 )) || break; fi
        if ! process_skills "$input"; then ui_notice "Skill error: $SKILL_ERROR" "$RED"; continue; fi
        [[ -z "$SKILL_NOTICE" ]] || ui_notice "$SKILL_NOTICE" "$GRAY"
        run_chat_turn "$input" "$SKILL_PROMPT" || true
    done
}

akro_require_commands || exit 1
mkdir -p "$AKRO_RUNTIME_DIR"
project_init_root
if ! ollama_choose_default; then printf 'Could not find installed Ollama models. Is Ollama running?\n' >&2; exit 1; fi
if [[ ! -t 0 || ! -t 1 ]]; then printf 'chat.sh needs an interactive terminal.\n' >&2; exit 1; fi
ui_redraw
printf '%bType /help for commands. Skills are slash commands at the end of a request.%b\n\n' "$GRAY" "$RESET"
main_loop
