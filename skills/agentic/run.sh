#!/usr/bin/env bash
set -uo pipefail

source "$AKRO_ROOT/config.sh"
source "$AKRO_ROOT/lib/common.sh"

TASK="$(cat)"
[[ -n "$(akro_trim "$TASK")" ]] || { printf 'Give /agentic a task to complete.\n' >&2; exit 1; }
[[ -n "${BASE_MODEL:-}" ]] || { printf 'Agentic requires the current Akro model.\n' >&2; exit 1; }

TTY="/dev/tty"
[[ -r "$TTY" && -w "$TTY" ]] || TTY=""
ACTIVE_PID=0
AGENT_LOG_DIR="${CURRENT_PROJECT_DIR:-$AKRO_DATA_DIR}/agent-runs"
mkdir -p "$AGENT_LOG_DIR" "$AKRO_RUNTIME_DIR"
RUN_ID="$(date '+%Y%m%d-%H%M%S')-$$"
LOG_FILE="$AGENT_LOG_DIR/$RUN_ID.jsonl"

agent_log() {
    local event="${1:-unknown}" payload="${2:-}"
    jq -cn --arg event "$event" --arg time "$(date '+%Y-%m-%dT%H:%M:%S%z')" --arg payload "$payload" \
        '{event:$event,time:$time,payload:$payload}' >> "$LOG_FILE" 2>/dev/null || true
}
agent_tty() { [[ -n "$TTY" ]] && printf "$@" > "$TTY" || true; }
agent_line() { [[ "${AGENT_VERBOSE:-1}" == 1 ]] && agent_tty '%s\n' "$1" || true; }
agent_spinner_wait() {
    local pid="$1" label="${2:-thinking}" frame=0 spinner="" rc=0
    local -a cycle=('⠾' '⠽' '⠻' '⠟' '⠯' '⠟' '⠻' '⠽')
    if [[ -z "$TTY" || "${AKRO_SHOW_ACTIVITY:-1}" != 1 ]]; then wait "$pid" || rc=$?; return "$rc"; fi
    tput civis > "$TTY" 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        spinner="${cycle[$((frame % ${#cycle[@]}))]}"
        printf '\r\033[0;90m[%s %s...]\033[0m' "$spinner" "$label" > "$TTY"
        frame=$((frame+1)); sleep 0.10
    done
    wait "$pid" || rc=$?
    printf '\r\033[2K' > "$TTY"
    tput cnorm > "$TTY" 2>/dev/null || true
    return "$rc"
}
agent_abort() {
    (( ACTIVE_PID > 0 )) && kill "$ACTIVE_PID" 2>/dev/null || true
    [[ -n "$TTY" ]] && { printf '\r\033[2K\033[1;33m[agentic aborted]\033[0m\n' > "$TTY"; tput cnorm > "$TTY" 2>/dev/null || true; }
    agent_log abort 'user interrupt'
    exit 130
}
trap agent_abort INT TERM

BASE_WORKSPACE="${AKRO_WORKSPACE:-$PWD}"
BASE_WORKSPACE="$(cd "$BASE_WORKSPACE" 2>/dev/null && pwd -P)" || { printf 'Could not resolve workspace.\n' >&2; exit 1; }
WORKSPACE="$BASE_WORKSPACE"
if [[ -n "${AKRO_SKILL_ARG:-}" ]]; then
    arg="$AKRO_SKILL_ARG"
    [[ "$arg" != /* && ! "/$arg/" =~ /\.\./ ]] || { printf 'Agent workspace argument must stay inside the launch workspace.\n' >&2; exit 1; }
    WORKSPACE="$(cd "$BASE_WORKSPACE/$arg" 2>/dev/null && pwd -P)" || { printf 'Agent workspace does not exist: %s\n' "$arg" >&2; exit 1; }
    case "$WORKSPACE" in "$BASE_WORKSPACE"|"$BASE_WORKSPACE"/*) ;; *) printf 'Agent workspace escaped launch workspace.\n' >&2; exit 1 ;; esac
fi

agent_header() {
    agent_tty '\n\033[1;35m╭─ AGENTIC ─────────────────────────────╮\033[0m\n'
    agent_tty '│ Model      %s\n' "${BASE_MODEL%:latest}"
    agent_tty '│ Executor   %s\n' "${AGENT_MODEL%:latest}"
    agent_tty '│ Workspace  %s\n' "$WORKSPACE"
    agent_tty '\033[1;35m╰───────────────────────────────────────╯\033[0m\n\n'
}
agent_confirm() {
    local title="$1" detail="$2" answer=""
    [[ -n "$TTY" ]] || return 1
    agent_tty '\n\033[1;33m╭─ Permission required ─────────────────╮\033[0m\n'
    agent_tty '│ %s\n' "$title"
    while IFS= read -r line; do agent_tty '│ %s\n' "$line"; done <<< "$detail"
    agent_tty '\033[1;33m╰───────────────────────────────────────╯\033[0m\nAllow? [y/N] '
    IFS= read -r answer < "$TTY" || answer=""
    case "$answer" in y|Y|yes|YES) agent_log permission "allowed: $title"; return 0 ;; *) agent_tty '\n'; agent_log permission "denied: $title"; return 1 ;; esac
}

# ---------- Model calls ----------
CONTROLLER_SCHEMA='{"type":"object","properties":{"status":{"type":"string","enum":["continue","done"]},"plan":{"type":"array","items":{"type":"string"}},"instruction":{"type":"string"},"note":{"type":"string"},"final":{"type":"string"}},"required":["status","plan","instruction","note","final"],"additionalProperties":false}'

agent_model_json() {
    local model="$1" system="$2" user="$3" schema="$4" ctx="$5" predict="$6" label="$7" out="" err="" payload="" rc=0 raw="" api_error="" content=""
    out="$(mktemp "$AKRO_RUNTIME_DIR/model-out.XXXXXX")"; err="$(mktemp "$AKRO_RUNTIME_DIR/model-err.XXXXXX")"
    payload="$(jq -n --arg model "$model" --arg system "$system" --arg user "$user" --argjson schema "$schema" --argjson ctx "$ctx" --argjson predict "$predict" '{model:$model,messages:[{role:"system",content:$system},{role:"user",content:$user}],stream:false,think:false,format:$schema,keep_alive:"5m",options:{temperature:0.05,top_p:0.9,num_ctx:$ctx,num_predict:$predict}}')"
    curl -sS --connect-timeout 10 --max-time 360 -H 'Content-Type: application/json' -d "$payload" "$OLLAMA_CHAT_URL" > "$out" 2> "$err" & ACTIVE_PID=$!
    agent_spinner_wait "$ACTIVE_PID" "$label" || rc=$?; ACTIVE_PID=0
    (( rc==0 )) || { cat "$err" >&2; rm -f "$out" "$err"; return "$rc"; }
    raw="$(cat "$out")"; api_error="$(jq -r '.error//empty' <<< "$raw" 2>/dev/null || true)"; [[ -z "$api_error" ]] || { printf '%s\n' "$api_error" >&2; rm -f "$out" "$err"; return 1; }
    content="$(jq -r '.message.content//empty' <<< "$raw" 2>/dev/null || true)"; rm -f "$out" "$err"
    jq -c '.' <<< "$content" 2>/dev/null
}

agent_model_text() {
    local model="$1" system="$2" user="$3" ctx="$4" predict="$5" label="$6" out="" err="" payload="" rc=0 raw="" api_error=""
    out="$(mktemp "$AKRO_RUNTIME_DIR/model-text.XXXXXX")"; err="$(mktemp "$AKRO_RUNTIME_DIR/model-err.XXXXXX")"
    payload="$(jq -n --arg model "$model" --arg system "$system" --arg user "$user" --argjson ctx "$ctx" --argjson predict "$predict" '{model:$model,messages:[{role:"system",content:$system},{role:"user",content:$user}],stream:false,think:false,keep_alive:"5m",options:{temperature:0,top_p:0.9,num_ctx:$ctx,num_predict:$predict}}')"
    curl -sS --connect-timeout 10 --max-time 360 -H 'Content-Type: application/json' -d "$payload" "$OLLAMA_CHAT_URL" > "$out" 2> "$err" & ACTIVE_PID=$!
    agent_spinner_wait "$ACTIVE_PID" "$label" || rc=$?; ACTIVE_PID=0
    (( rc==0 )) || { cat "$err" >&2; rm -f "$out" "$err"; return "$rc"; }
    raw="$(cat "$out")"; api_error="$(jq -r '.error//empty' <<< "$raw" 2>/dev/null || true)"; [[ -z "$api_error" ]] || { printf '%s\n' "$api_error" >&2; rm -f "$out" "$err"; return 1; }
    jq -r '.message.content//empty' <<< "$raw" 2>/dev/null
    rm -f "$out" "$err"
}

CONTROLLER_SYSTEM="You supervise Akro Agentic. You understand the user's task, make a short plain-English plan, choose one next outcome, review the exact action Akro executed and its result, and write the final answer.

Rules:
- Keep plans and instructions in plain English. Do not write Akro action protocol lines.
- Preserve exact filenames, paths, text, and constraints from the user.
- Give exactly one next instruction when status=continue.
- Review the ACTION and RESULT from this run. If the executor did the wrong thing, correct course.
- Never claim an action happened unless this run's ACTION/RESULT proves it.
- For changes, verify important results before status=done when practical.
- status=done only when the user's task is actually complete or safe progress is impossible.
"

EXECUTOR_SYSTEM='You are Coral Agent, a tiny action compiler. Convert ONE instruction into exactly ONE Akro action line. Return no explanation and no Markdown.

Actions:
READ|path
WRITE|path|content
APPEND|path|content
REPLACE|path|old|new
DELETE|path
EXISTS|path
LIST|path
SEARCH|path|query
SHELL|command
WEB|query

Escapes inside arguments:
\\ = literal backslash
\| = literal pipe
\n = newline
\t = tab
\r = carriage return

Rules:
- Output one physical line only.
- Use workspace-relative paths when possible.
- Do not invent extra fields.
- SHELL takes one complete shell command string.
- WEB takes a search query, not a URL-fetch instruction.
- Pick the simplest action that directly performs the instruction.'

# ---------- Action protocol ----------
ACTION=""; ACTION_ARGS=()
agent_split_action() {
    local line="$1" i ch escaped=0 field=""
    ACTION=""; ACTION_ARGS=(); ACTION_FIELDS=()
    for ((i=0; i<${#line}; i++)); do
        ch="${line:i:1}"
        if (( escaped )); then field+="\\$ch"; escaped=0; continue; fi
        if [[ "$ch" == "\\" ]]; then escaped=1; continue; fi
        if [[ "$ch" == "|" ]]; then ACTION_FIELDS+=("$field"); field=""; else field+="$ch"; fi
    done
    (( escaped )) && field+='\'
    ACTION_FIELDS+=("$field")
    ACTION="${ACTION_FIELDS[0]:-}"
    local idx raw decoded
    for ((idx=1; idx<${#ACTION_FIELDS[@]}; idx++)); do
        raw="${ACTION_FIELDS[$idx]}"; decoded=""; escaped=0
        for ((i=0; i<${#raw}; i++)); do
            ch="${raw:i:1}"
            if (( escaped )); then
                case "$ch" in n) decoded+=$'\n' ;; t) decoded+=$'\t' ;; r) decoded+=$'\r' ;; '\') decoded+='\' ;; '|') decoded+='|' ;; *) return 1 ;; esac
                escaped=0
            elif [[ "$ch" == "\\" ]]; then escaped=1
            else decoded+="$ch"
            fi
        done
        (( escaped )) && return 1
        ACTION_ARGS+=("$decoded")
    done
    return 0
}
agent_expected_args() {
    case "$1" in READ|DELETE|EXISTS|LIST|SHELL|WEB) echo 1 ;; WRITE|APPEND|SEARCH) echo 2 ;; REPLACE) echo 3 ;; *) echo -1 ;; esac
}
agent_parse_action() {
    local raw="$1" expected="" lines=""
    raw="${raw%$'\r'}"
    [[ -n "$raw" ]] || { ACTION_ERROR='empty action'; return 1; }
    [[ ${#raw} -le ${AGENT_ACTION_MAX_CHARS:-100000} ]] || { ACTION_ERROR='action exceeds size limit'; return 1; }
    lines="$(printf '%s' "$raw" | awk 'END{print NR}')"
    [[ "$lines" == 1 ]] || { ACTION_ERROR='return exactly one physical line'; return 1; }
    agent_split_action "$raw" || { ACTION_ERROR='invalid escape sequence'; return 1; }
    [[ "$ACTION" =~ ^[A-Z_]+$ ]] || { ACTION_ERROR='invalid action name'; return 1; }
    expected="$(agent_expected_args "$ACTION")"
    [[ "$expected" != -1 ]] || { ACTION_ERROR="unknown action $ACTION"; return 1; }
    [[ ${#ACTION_ARGS[@]} -eq $expected ]] || { ACTION_ERROR="$ACTION requires $expected argument(s), got ${#ACTION_ARGS[@]}"; return 1; }
    return 0
}
agent_escape_preview() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e ':a;N;$!ba;s/\n/\\n/g' -e 's/|/\\|/g' | head -c 500; }
agent_action_display() {
    local out="$ACTION" arg
    for arg in "${ACTION_ARGS[@]}"; do out+="|$(agent_escape_preview "$arg")"; done
    printf '%s' "$out"
}

# ---------- Workspace paths ----------
agent_sensitive_path() { case "/$1/" in */.env/*|*/.env/|*/.ssh/*|*/.aws/*|*/.config/gcloud/*|*/Library/Keychains/*|*/.git/*|*/.git/) return 0 ;; *) return 1 ;; esac; }
agent_path() {
    local input="$1" mode="${2:-read}" candidate="" parent="" base="" resolved=""
    [[ -n "$input" ]] || input='.'
    if [[ "$input" == /* ]]; then candidate="$input"; else candidate="$WORKSPACE/$input"; fi
    if [[ -e "$candidate" ]]; then
        if [[ -d "$candidate" ]]; then resolved="$(cd "$candidate" 2>/dev/null && pwd -P)" || return 1
        else parent="$(dirname "$candidate")"; base="$(basename "$candidate")"; parent="$(cd "$parent" 2>/dev/null && pwd -P)" || return 1; resolved="$parent/$base"
        fi
    else
        [[ "$mode" != read ]] || return 1
        parent="$(dirname "$candidate")"; base="$(basename "$candidate")"; parent="$(cd "$parent" 2>/dev/null && pwd -P)" || return 1; resolved="$parent/$base"
    fi
    case "$resolved" in "$WORKSPACE"|"$WORKSPACE"/*) ;; *) printf 'ERROR: path escapes workspace: %s\n' "$input"; return 2 ;; esac
    if agent_sensitive_path "$resolved"; then agent_confirm 'Access sensitive path' "$resolved" || return 3; fi
    printf '%s' "$resolved"
}
agent_rel() { case "$1" in "$WORKSPACE") printf '.' ;; "$WORKSPACE"/*) printf '%s' "${1#"$WORKSPACE"/}" ;; *) printf '%s' "$1" ;; esac; }

# ---------- Permissions and execution ----------
agent_shell_safe() {
    local c="$1"
    case "$c" in *';'*|'*|'*|'*&&'*|'*||'*|'*>'*|'*<'*|'*`'*|'*$('*|'*${'*) return 1 ;; esac
    [[ "$c" =~ ^[[:space:]]*(pwd|ls)([[:space:]]|$) ]] && return 0
    [[ "$c" =~ ^[[:space:]]*(rg|grep|cat|head|tail|wc|stat)([[:space:]]|$) ]] && return 0
    [[ "$c" =~ ^[[:space:]]*git[[:space:]]+(status|diff|log|show)([[:space:]]|$) ]] && return 0
    return 1
}
agent_command_timeout() {
    local cmd="$1" out="" rc=0 timer=0 timeout_s="${AGENT_COMMAND_TIMEOUT:-120}"
    out="$(mktemp "$AKRO_RUNTIME_DIR/cmd-out.XXXXXX")"
    (cd "$WORKSPACE" && bash -lc "$cmd") > "$out" 2>&1 & ACTIVE_PID=$!
    (sleep "$timeout_s"; kill "$ACTIVE_PID" 2>/dev/null || true) & timer=$!
    wait "$ACTIVE_PID" || rc=$?; ACTIVE_PID=0
    kill "$timer" 2>/dev/null || true; wait "$timer" 2>/dev/null || true
    head -c "${AGENT_MAX_TOOL_OUTPUT:-16000}" "$out"; rm -f "$out"; return "$rc"
}
agent_web() {
    local query="$1" payload="" response=""
    [[ -n "${TAVILY_API_KEY:-}" ]] || { printf 'ERROR: TAVILY_API_KEY is not set.\n'; return 1; }
    agent_confirm 'Search the web' "$query" || { printf 'DENIED: web search not approved.\n'; return 2; }
    payload="$(jq -n --arg query "$query" --argjson max "${TAVILY_MAX_RESULTS:-5}" '{query:$query,search_depth:"advanced",max_results:$max,include_answer:"advanced"}')"
    response="$(curl -sS --connect-timeout 10 --max-time 45 -H "Authorization: Bearer $TAVILY_API_KEY" -H 'Content-Type: application/json' -d "$payload" "${TAVILY_API_URL:-https://api.tavily.com/search}" 2>&1)" || { printf '%s\n' "$response"; return 1; }
    jq -r '(if (.answer//"")!="" then "Summary: "+.answer+"\n" else "" end)+(.results|to_entries|map("["+((.key+1)|tostring)+"] "+(.value.title//"Untitled")+"\nURL: "+(.value.url//"")+"\n"+((.value.content//"")|.[0:1200]))|join("\n\n"))' <<< "$response" | head -c "${AGENT_MAX_TOOL_OUTPUT:-16000}"
}
agent_execute_action() {
    local p="" old="" new="" count=0 tmp="" cmd="" query=""
    case "$ACTION" in
        READ)
            p="$(agent_path "${ACTION_ARGS[0]}" read)" || return $?
            [[ -f "$p" ]] || { printf 'ERROR: not a file.\n'; return 1; }
            head -c "${AGENT_MAX_READ_CHARS:-20000}" "$p"
            ;;
        WRITE)
            p="$(agent_path "${ACTION_ARGS[0]}" write)" || return $?
            [[ ${#ACTION_ARGS[1]} -le ${AGENT_MAX_WRITE_CHARS:-80000} ]] || { printf 'ERROR: content too large.\n'; return 1; }
            mkdir -p "$(dirname "$p")"; printf '%s' "${ACTION_ARGS[1]}" > "$p"
            printf 'OK: wrote %s bytes to %s\n' "$(wc -c < "$p" | tr -d ' ')" "$(agent_rel "$p")"
            ;;
        APPEND)
            p="$(agent_path "${ACTION_ARGS[0]}" write)" || return $?
            [[ ${#ACTION_ARGS[1]} -le ${AGENT_MAX_WRITE_CHARS:-80000} ]] || { printf 'ERROR: content too large.\n'; return 1; }
            printf '%s' "${ACTION_ARGS[1]}" >> "$p"; printf 'OK: appended to %s\n' "$(agent_rel "$p")"
            ;;
        REPLACE)
            p="$(agent_path "${ACTION_ARGS[0]}" read)" || return $?
            [[ -f "$p" ]] || { printf 'ERROR: not a file.\n'; return 1; }
            old="${ACTION_ARGS[1]}"; new="${ACTION_ARGS[2]}"
            count="$(python3 - "$p" "$old" <<'PY'
import sys
p, old = sys.argv[1], sys.argv[2]
with open(p, 'r', encoding='utf-8') as f: s=f.read()
print(s.count(old))
PY
)" || return 1
            [[ "$count" == 1 ]] || { printf 'ERROR: old text matched %s times; expected exactly 1.\n' "$count"; return 1; }
            tmp="$(mktemp "$AKRO_RUNTIME_DIR/replace.XXXXXX")"
            python3 - "$p" "$tmp" "$old" "$new" <<'PY'
import sys
p,tmp,old,new=sys.argv[1:]
with open(p,'r',encoding='utf-8') as f: s=f.read()
with open(tmp,'w',encoding='utf-8') as f: f.write(s.replace(old,new,1))
PY
            cat "$tmp" > "$p"; rm -f "$tmp"; printf 'OK: replaced text in %s\n' "$(agent_rel "$p")"
            ;;
        DELETE)
            p="$(agent_path "${ACTION_ARGS[0]}" read)" || return $?
            [[ -f "$p" ]] || { printf 'ERROR: DELETE only supports existing files.\n'; return 1; }
            agent_confirm 'Delete file' "$(agent_rel "$p")" || { printf 'DENIED: delete not approved.\n'; return 2; }
            rm -- "$p"; printf 'OK: deleted %s\n' "$(agent_rel "$p")"
            ;;
        EXISTS)
            if p="$(agent_path "${ACTION_ARGS[0]}" write 2>/dev/null)"; then [[ -e "$p" ]] && printf 'TRUE\n' || printf 'FALSE\n'; else printf 'FALSE\n'; fi
            ;;
        LIST)
            p="$(agent_path "${ACTION_ARGS[0]}" read)" || return $?
            [[ -d "$p" ]] || { printf 'ERROR: not a directory.\n'; return 1; }
            (cd "$p" && ls -1A 2>/dev/null | head -n 200)
            ;;
        SEARCH)
            p="$(agent_path "${ACTION_ARGS[0]}" read)" || return $?
            query="${ACTION_ARGS[1]}"
            if command -v rg >/dev/null 2>&1; then rg -n -F --hidden -g '!.git/**' -- "$query" "$p" 2>&1 | head -c "${AGENT_MAX_TOOL_OUTPUT:-16000}"; else grep -R -n -F --exclude-dir=.git -- "$query" "$p" 2>&1 | head -c "${AGENT_MAX_TOOL_OUTPUT:-16000}"; fi
            ;;
        SHELL)
            cmd="${ACTION_ARGS[0]}"
            if ! agent_shell_safe "$cmd"; then agent_confirm 'Run shell command' "$cmd" || { printf 'DENIED: command not approved.\n'; return 2; }; fi
            agent_command_timeout "$cmd"
            ;;
        WEB) agent_web "${ACTION_ARGS[0]}" ;;
        *) printf 'ERROR: unknown action.\n'; return 1 ;;
    esac
}

agent_mutates() { case "$1" in WRITE|APPEND|REPLACE|DELETE|SHELL) return 0 ;; *) return 1 ;; esac; }

# ---------- Executor repair ----------
agent_executor() {
    local instruction="$1" repair="${2:-}" user="Instruction:\n$instruction"
    [[ -z "$repair" ]] || user+="\n\nYour previous output was invalid:\n$repair\nReturn one corrected action line only."
    agent_model_text "$AGENT_MODEL" "$EXECUTOR_SYSTEM" "$user" "${AGENT_NUM_CTX:-4096}" "${AGENT_NUM_PREDICT:-300}" 'executor choosing action'
}

# ---------- Self test ----------
if [[ "${AGENT_SELF_TEST:-0}" == 1 ]]; then
    agent_parse_action 'WRITE|x.txt|hello\nworld\|ok\\done' || { echo 'self-test: valid action rejected' >&2; exit 1; }
    [[ "$ACTION" == WRITE && ${#ACTION_ARGS[@]} -eq 2 ]] || exit 1
    [[ "${ACTION_ARGS[1]}" == $'hello\nworld|ok\\done' ]] || { echo 'self-test: escaping failed' >&2; exit 1; }
    if agent_parse_action $'READ|a\nREAD|b'; then echo 'self-test: multiline output accepted' >&2; exit 1; fi
    agent_parse_action 'WRITE|.agent-v4-test.txt|ok\n' || exit 1
    agent_execute_action >/dev/null || { echo 'self-test: write failed' >&2; exit 1; }
    [[ "$(wc -c < "$WORKSPACE/.agent-v4-test.txt" | tr -d ' ')" == 3 ]] || { echo 'self-test: newline write failed' >&2; exit 1; }
    agent_parse_action 'READ|.agent-v4-test.txt' || exit 1
    [[ "$(agent_execute_action)" == ok ]] || { echo 'self-test: read failed' >&2; exit 1; }
    agent_parse_action 'EXISTS|.agent-v4-test.txt' || exit 1
    [[ "$(agent_execute_action)" == TRUE ]] || { echo 'self-test: exists failed' >&2; exit 1; }
    rm -f "$WORKSPACE/.agent-v4-test.txt"
    echo 'Agentic v4 self-test passed.'
    exit 0
fi

# ---------- Main loop ----------
agent_header
agent_log start "task=$TASK | workspace=$WORKSPACE | model=$BASE_MODEL | executor=$AGENT_MODEL | protocol=v4"
PLAN='[]'; LAST_ACTION='(none)'; LAST_RESULT='No action has run yet.'; success_count=0; step=1; final_response=''; prev_action=''; consecutive_repeat=0
ACTION_HISTORY_FILE="$(mktemp "$AKRO_RUNTIME_DIR/action-history.XXXXXX")"

while (( step <= ${AGENT_MAX_STEPS:-12} )); do
    controller_user="USER TASK:\n$TASK\n\nPLAN SO FAR:\n$PLAN\n\nLAST ACTION:\n$LAST_ACTION\n\nLAST RESULT:\n$LAST_RESULT\n\nSuccessful actions this run: $success_count\n\nChoose the next outcome or finish."
    controller="$(agent_model_json "$BASE_MODEL" "$CONTROLLER_SYSTEM" "$controller_user" "$CONTROLLER_SCHEMA" "${AGENT_CONTROLLER_NUM_CTX:-8192}" "${AGENT_CONTROLLER_NUM_PREDICT:-900}" 'supervisor thinking')" || { final_response='Agentic stopped because the supervisor model failed.'; break; }
    agent_log supervisor "$controller"
    PLAN="$(jq -c '.plan // []' <<< "$controller")"; status="$(jq -r '.status' <<< "$controller")"; instruction="$(jq -r '.instruction // empty' <<< "$controller")"; note="$(jq -r '.note // empty' <<< "$controller")"
    if [[ "${AGENT_SHOW_PLAN:-1}" == 1 && "$step" == 1 ]]; then
        agent_tty '\033[1;35m◆ Plan\033[0m\n'; jq -r 'to_entries[] | "  \(.key+1). \(.value)"' <<< "$PLAN" | while IFS= read -r l; do agent_tty '%s\n' "$l"; done; agent_tty '\n'
    elif [[ -n "$note" && "${AGENT_VERBOSE:-1}" == 1 ]]; then agent_tty '\033[1;35m◆ Supervisor\033[0m %s\n\n' "$note"; fi

    if [[ "$status" == done ]]; then
        if (( success_count == 0 )); then
            LAST_RESULT='COMPLETION REJECTED: no action from this Agentic run has succeeded. Give one concrete next instruction.'
            agent_line '⚠ completion rejected: no successful action in this run'
            step=$((step+1)); continue
        fi
        final_response="$(jq -r '.final // empty' <<< "$controller")"; [[ -n "$final_response" ]] || final_response='Agentic task complete.'; break
    fi
    [[ -n "$instruction" ]] || { LAST_RESULT='SUPERVISOR ERROR: no next instruction was provided.'; step=$((step+1)); continue; }

    if [[ "${AGENT_SHOW_INSTRUCTIONS:-1}" == 1 ]]; then agent_tty '\033[1;36m╭─ Instruction %s\033[0m\n│ %s\n\033[1;36m╰───────────────────────────────────────\033[0m\n' "$step" "$instruction"; fi

    raw_action="$(agent_executor "$instruction")" || raw_action=''
    ACTION_ERROR=''; repair=''
    if ! agent_parse_action "$raw_action"; then
        repair="$ACTION_ERROR. Output was: $(printf '%s' "$raw_action" | head -c 500)"
        agent_line "✕ invalid action: $ACTION_ERROR"
        raw_action="$(agent_executor "$instruction" "$repair")" || raw_action=''
        ACTION_ERROR=''
        if ! agent_parse_action "$raw_action"; then
            LAST_ACTION='(invalid)'; LAST_RESULT="EXECUTOR FAILED: $ACTION_ERROR. Give a simpler instruction."; agent_log executor_failure "$LAST_RESULT"; step=$((step+1)); continue
        fi
    fi

    display_action="$(agent_action_display)"
    if [[ "$display_action" == "$prev_action" ]]; then consecutive_repeat=$((consecutive_repeat+1)); else consecutive_repeat=1; fi
    prev_action="$display_action"
    count="$(grep -Fxc -- "$display_action" "$ACTION_HISTORY_FILE" 2>/dev/null || true)"; count=$((count+1)); printf '%s\n' "$display_action" >> "$ACTION_HISTORY_FILE"
    if (( consecutive_repeat > 1 )); then LAST_ACTION="$display_action"; LAST_RESULT='REPEAT BLOCKED: identical action requested twice consecutively. Choose a different next step.'; agent_line '⚠ repeated action blocked'; step=$((step+1)); continue; fi
    if (( count > 3 )); then final_response='Agentic stopped because the same action was requested too many times.'; break; fi

    [[ "${AGENT_SHOW_TOOLS:-1}" == 1 ]] && agent_tty '\n\033[1;34m→ %s\033[0m\n' "$display_action"
    agent_log action "$display_action"
    out="$(mktemp "$AKRO_RUNTIME_DIR/action-out.XXXXXX")"; rc=0
    agent_execute_action > "$out" 2>&1 || rc=$?
    result="$(head -c "${AGENT_MAX_TOOL_OUTPUT:-16000}" "$out")"; rm -f "$out"; [[ -n "$result" ]] || result='(no output)'
    if (( rc==0 )); then agent_tty '\033[1;32m✓ action completed\033[0m\n'; success_count=$((success_count+1)); else agent_tty '\033[1;31m✕ action returned rc=%s\033[0m\n' "$rc"; fi
    [[ "${AGENT_VERBOSE:-1}" == 1 ]] && printf '%s\n' "$result" | head -n 12 | while IFS= read -r l; do agent_tty '  %s\n' "$l"; done
    agent_tty '\n'
    LAST_ACTION="$display_action"; LAST_RESULT="rc=$rc\n$result"; agent_log result "action=$display_action rc=$rc result=$(printf '%s' "$result" | head -c 3000)"
    step=$((step+1))
done

if [[ -z "$final_response" ]]; then
    wrap_user="USER TASK:\n$TASK\n\nLAST ACTION:\n$LAST_ACTION\n\nLAST RESULT:\n$LAST_RESULT\n\nAkro stopped at its action limit. Give a truthful final summary based only on actions/results from this run."
    controller="$(agent_model_json "$BASE_MODEL" "$CONTROLLER_SYSTEM" "$wrap_user" "$CONTROLLER_SCHEMA" "${AGENT_CONTROLLER_NUM_CTX:-8192}" "${AGENT_CONTROLLER_NUM_PREDICT:-900}" 'supervisor wrapping up')" || true
    final_response="$(jq -r '.final // "Agentic stopped before the task was fully completed."' <<< "${controller:-{}}" 2>/dev/null || printf 'Agentic stopped before the task was fully completed.')"
fi

rm -f "${ACTION_HISTORY_FILE:-}" 2>/dev/null || true
agent_log final "$final_response"
agent_tty '\n\033[1;35m◆ Agentic complete\033[0m\n  log: %s\n\n' "$LOG_FILE"
jq -n --arg response "$final_response" --arg model "$BASE_MODEL" '{complete:true,response:$response,model:$model,notice:"Agentic task complete."}'
