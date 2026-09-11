#!/usr/bin/env bash
set -uo pipefail

source "$AKRO_ROOT/config.sh"
source "$AKRO_ROOT/lib/common.sh"
source "$AKRO_ROOT/lib/ollama.sh"

TASK="$(cat)"
[[ -n "$(akro_trim "$TASK")" ]] || { printf 'Give /agentic a task to complete.\n' >&2; exit 1; }

TTY="/dev/tty"
[[ -w "$TTY" && -r "$TTY" ]] || TTY=""
ACTIVE_AGENT_PID=0
agent_abort() {
    if (( ACTIVE_AGENT_PID > 0 )); then kill "$ACTIVE_AGENT_PID" 2>/dev/null || true; fi
    [[ -z "$TTY" ]] || { printf '\r\033[2K[agent aborted]\n' > "$TTY"; tput cnorm > "$TTY" 2>/dev/null || true; }
    exit 130
}
trap agent_abort INT TERM

agent_tty() {
    [[ -n "$TTY" ]] || return 0
    printf "$@" > "$TTY"
}

agent_notice() {
    [[ "${AGENT_SHOW_TOOLS:-1}" == "1" ]] || return 0
    agent_tty '%s\n' "$1"
}

agent_spin_wait() {
    local pid="$1" label="${2:-agent thinking}" frame=0 spinner="" rc=0
    local -a cycle=('⠾' '⠽' '⠻' '⠟' '⠯' '⠟' '⠻' '⠽')
    if [[ -z "$TTY" || "${AKRO_SHOW_ACTIVITY:-1}" != "1" ]]; then wait "$pid" || rc=$?; return "$rc"; fi
    tput civis > "$TTY" 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        spinner="${cycle[$((frame % ${#cycle[@]}))]}"
        printf '\r\033[0;90m[%s %s...]\033[0m' "$spinner" "$label" > "$TTY"
        frame=$((frame + 1))
        sleep 0.10
    done
    wait "$pid" || rc=$?
    printf '\r\033[2K' > "$TTY"
    tput cnorm > "$TTY" 2>/dev/null || true
    return "$rc"
}

agent_confirm() {
    local description="$1" answer=""
    [[ "${AGENT_CONFIRM_WRITES:-1}" == "1" ]] || return 0
    [[ -n "$TTY" ]] || return 1
    agent_tty '\n\033[1;33m%s\033[0m\nAllow? [y/N] ' "$description"
    IFS= read -r answer < "$TTY" || answer=""
    case "$answer" in y|Y|yes|YES) return 0 ;; *) agent_tty '\n'; return 1 ;; esac
}

BASE_WORKSPACE="${AKRO_WORKSPACE:-$PWD}"
if ! BASE_WORKSPACE="$(cd "$BASE_WORKSPACE" 2>/dev/null && pwd -P)"; then
    printf 'Could not resolve agent workspace: %s\n' "${AKRO_WORKSPACE:-$PWD}" >&2
    exit 1
fi
WORKSPACE="$BASE_WORKSPACE"

if [[ -n "${AKRO_SKILL_ARG:-}" ]]; then
    arg="$AKRO_SKILL_ARG"
    [[ "$arg" != /* ]] || { printf 'Agent workspace argument must be relative to the current workspace.\n' >&2; exit 1; }
    [[ ! "/$arg/" =~ /\.\./ ]] || { printf 'Agent workspace cannot escape the current workspace.\n' >&2; exit 1; }
    if ! WORKSPACE="$(cd "$BASE_WORKSPACE/$arg" 2>/dev/null && pwd -P)"; then
        printf 'Agent workspace does not exist: %s\n' "$arg" >&2
        exit 1
    fi
    case "$WORKSPACE" in "$BASE_WORKSPACE"|"$BASE_WORKSPACE"/*) ;; *) printf 'Agent workspace escaped the current directory.\n' >&2; exit 1 ;; esac
fi

ollama_model_exists "$AGENT_MODEL" || {
    printf 'Agent model is not installed: %s\nPull or create coral1.6-agent, then try again.\n' "$AGENT_MODEL" >&2
    exit 1
}

AGENT_RUN_DIR="$CURRENT_PROJECT_DIR/agent/runs"
mkdir -p "$AGENT_RUN_DIR"
RUN_ID="$(date '+%Y%m%d-%H%M%S')-$$"
LOG_FILE="$AGENT_RUN_DIR/$RUN_ID.jsonl"

agent_log() {
    printf '%s\n' "$1" >> "$LOG_FILE"
}
agent_log "$(jq -nc --arg time "$(akro_timestamp)" --arg task "$TASK" --arg workspace "$WORKSPACE" --arg model "$AGENT_MODEL" '{event:"start",time:$time,task:$task,workspace:$workspace,model:$model}')"

agent_protected_path() {
    local path="$1"
    [[ "/$path/" =~ /\.git/ || "/$path/" =~ /\.env/ || "/$path/" =~ /\.ssh/ ]]
}

agent_resolve_path() {
    local path="${1:-.}" allow_new="${2:-0}" dir="" base="" absdir="" abs=""
    [[ -n "$path" ]] || path="."
    [[ "$path" != /* ]] || return 1
    [[ ! "/$path/" =~ /\.\./ ]] || return 1
    agent_protected_path "$path" && return 1
    if [[ "$path" == "." ]]; then printf '%s' "$WORKSPACE"; return 0; fi
    dir="$(dirname "$path")"; base="$(basename "$path")"
    absdir="$(cd "$WORKSPACE/$dir" 2>/dev/null && pwd -P)" || return 1
    case "$absdir" in "$WORKSPACE"|"$WORKSPACE"/*) ;; *) return 1 ;; esac
    abs="$absdir/$base"
    if [[ -L "$abs" ]]; then return 1; fi
    if [[ "$allow_new" != "1" && ! -e "$abs" ]]; then return 1; fi
    printf '%s' "$abs"
}

agent_rel_path() {
    local abs="$1"
    if [[ "$abs" == "$WORKSPACE" ]]; then printf '.'; else printf '%s' "${abs#"$WORKSPACE"/}"; fi
}

agent_cap() {
    head -c "${AGENT_MAX_TOOL_OUTPUT:-12000}"
}

agent_context() {
    [[ "${CURRENT_PROJECT_SLUG:-}" != "sandbox" ]] || return 0
    local words="" wf="" dir="" file="" count=0 used=0 max="${AGENT_CONTEXT_MAX_CHARS:-2200}" text=""
    words="$(akro_query_words "$TASK" | head -n 8)"
    [[ -n "$words" ]] || return 0
    wf="$(mktemp "$AKRO_RUNTIME_DIR/agent-words.XXXXXX")"
    printf '%s\n' "$words" > "$wf"
    for dir in "$CURRENT_PROJECT_DIR/brain/notes" "$AKRO_GLOBAL_DIR/brain/notes"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r file; do
            [[ -f "$file" ]] || continue
            text="$(head -c 1000 "$file")"
            printf '\n--- %s ---\n%s\n' "$(basename "$file")" "$text"
            count=$((count + 1)); used=$((used + ${#text}))
            (( count >= 2 || used >= max )) && { rm -f "$wf"; return 0; }
        done < <(grep -Fil -f "$wf" "$dir"/*.md 2>/dev/null | head -n 2)
    done
    rm -f "$wf"
}

agent_tool_list_files() {
    local path="${1:-.}" depth="${2:-2}" abs=""
    case "$depth" in ''|*[!0-9]*) depth=2 ;; esac
    (( depth < 1 )) && depth=1; (( depth > 4 )) && depth=4
    abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid, protected, or missing path: %s\n' "$path"; return 1; }
    [[ -d "$abs" ]] || { printf 'ERROR: not a directory: %s\n' "$path"; return 1; }
    find "$abs" -maxdepth "$depth" -mindepth 1 \( -name .git -o -name .env -o -name .ssh \) -prune -o -print 2>/dev/null \
        | sed "s#^$WORKSPACE/##" | head -n 300 | agent_cap
}

agent_tool_read_file() {
    local path="$1" start="${2:-1}" end="${3:-0}" abs="" size=0
    abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid, protected, or missing path: %s\n' "$path"; return 1; }
    [[ -f "$abs" && -r "$abs" ]] || { printf 'ERROR: not a readable file: %s\n' "$path"; return 1; }
    grep -Iq . "$abs" 2>/dev/null || { printf 'ERROR: binary/non-text file rejected: %s\n' "$path"; return 1; }
    case "$start" in ''|*[!0-9]*) start=1 ;; esac
    case "$end" in ''|*[!0-9]*) end=0 ;; esac
    (( start < 1 )) && start=1
    if (( end <= 0 )); then end=$((start + 249)); fi
    (( end < start )) && end=$start
    awk -v s="$start" -v e="$end" 'NR>=s && NR<=e {printf "%6d  %s\n", NR, $0}' "$abs" | head -c "${AGENT_MAX_READ_CHARS:-18000}"
}

agent_tool_search_files() {
    local query="$1" path="${2:-.}" abs=""
    [[ -n "$query" ]] || { printf 'ERROR: search query is empty.\n'; return 1; }
    abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid, protected, or missing path: %s\n' "$path"; return 1; }
    if command -v rg >/dev/null 2>&1; then
        rg -n --no-heading --hidden --glob '!.git/**' --glob '!.env' --glob '!.ssh/**' -- "$query" "$abs" 2>/dev/null | sed "s#^$WORKSPACE/##" | head -n 200 | agent_cap
    else
        grep -RIn --exclude-dir=.git --exclude-dir=.ssh --exclude=.env -- "$query" "$abs" 2>/dev/null | sed "s#^$WORKSPACE/##" | head -n 200 | agent_cap
    fi
}

agent_tool_write_file() {
    local path="$1" content="$2" abs="" tmp=""
    (( ${#content} <= ${AGENT_MAX_WRITE_CHARS:-50000} )) || { printf 'ERROR: write exceeds AGENT_MAX_WRITE_CHARS.\n'; return 1; }
    abs="$(agent_resolve_path "$path" 1)" || { printf 'ERROR: invalid or protected path: %s\n' "$path"; return 1; }
    agent_confirm "Agent wants to write: $(agent_rel_path "$abs")" || { printf 'DENIED: user declined file write.\n'; return 2; }
    tmp="$(mktemp "$(dirname "$abs")/.agent-write.XXXXXX")" || return 1
    printf '%s' "$content" > "$tmp" && mv "$tmp" "$abs"
    printf 'OK: wrote %s bytes to %s\n' "${#content}" "$(agent_rel_path "$abs")"
}

agent_tool_replace_text() {
    local path="$1" old="$2" new="$3" abs="" tmp="" count=0
    [[ -n "$old" ]] || { printf 'ERROR: old text cannot be empty.\n'; return 1; }
    abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid, protected, or missing path: %s\n' "$path"; return 1; }
    [[ -f "$abs" && -w "$abs" ]] || { printf 'ERROR: file is not writable: %s\n' "$path"; return 1; }
    command -v perl >/dev/null 2>&1 || { printf 'ERROR: replace_text requires perl on this machine. Use write_file instead.\n'; return 1; }
    count="$(OLD="$old" perl -0777 -ne '$o=$ENV{OLD}; $n=()=/\Q$o\E/g; print $n' "$abs" 2>/dev/null || printf 0)"
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    (( count > 0 )) || { printf 'ERROR: exact old text was not found.\n'; return 1; }
    agent_confirm "Agent wants to replace text in: $(agent_rel_path "$abs") ($count match(es))" || { printf 'DENIED: user declined text replacement.\n'; return 2; }
    tmp="$(mktemp "$(dirname "$abs")/.agent-replace.XXXXXX")" || return 1
    OLD="$old" NEW="$new" perl -0777 -pe '$o=$ENV{OLD};$n=$ENV{NEW};s/\Q$o\E/$n/g' "$abs" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$abs"
    printf 'OK: replaced %s match(es) in %s\n' "$count" "$(agent_rel_path "$abs")"
}

agent_tool_make_directory() {
    local path="$1" abs="" parent="" base=""
    [[ -n "$path" && "$path" != "." ]] || { printf 'ERROR: directory path is required.\n'; return 1; }
    [[ "$path" != /* && ! "/$path/" =~ /\.\./ ]] || { printf 'ERROR: invalid directory path.\n'; return 1; }
    agent_protected_path "$path" && { printf 'ERROR: protected directory path.\n'; return 1; }
    parent="$(dirname "$path")"; base="$(basename "$path")"
    abs="$(agent_resolve_path "$parent" 0)" || { printf 'ERROR: parent directory does not exist or is protected.\n'; return 1; }
    [[ -d "$abs" ]] || { printf 'ERROR: parent is not a directory.\n'; return 1; }
    abs="$abs/$base"
    case "$abs" in "$WORKSPACE"/*) ;; *) printf 'ERROR: path escaped workspace.\n'; return 1 ;; esac
    agent_confirm "Agent wants to create directory: ${abs#"$WORKSPACE"/}" || { printf 'DENIED: user declined directory creation.\n'; return 2; }
    mkdir -p "$abs" || return 1
    printf 'OK: created directory %s\n' "${abs#"$WORKSPACE"/}"
}

agent_tool_run_check() {
    local check="$1" path="${2:-}" abs="" rc=0
    case "$check" in
        git_status) (cd "$WORKSPACE" && git status --short 2>&1) | agent_cap ;;
        git_diff) (cd "$WORKSPACE" && git diff -- 2>&1) | agent_cap ;;
        git_diff_check) (cd "$WORKSPACE" && git diff --check 2>&1) | agent_cap ;;
        bash_n)
            abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid or protected path.\n'; return 1; }
            bash -n "$abs" 2>&1 && printf 'OK: bash syntax valid: %s\n' "$path"
            ;;
        jq)
            abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid or protected path.\n'; return 1; }
            jq empty "$abs" 2>&1 && printf 'OK: JSON valid: %s\n' "$path"
            ;;
        shellcheck)
            command -v shellcheck >/dev/null 2>&1 || { printf 'ERROR: shellcheck is not installed.\n'; return 1; }
            abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid or protected path.\n'; return 1; }
            shellcheck "$abs" 2>&1 | agent_cap
            ;;
        test_script)
            [[ "$path" == tests/* ]] || { printf 'ERROR: test_script is limited to tests/ inside the workspace.\n'; return 1; }
            abs="$(agent_resolve_path "$path" 0)" || { printf 'ERROR: invalid or protected test path.\n'; return 1; }
            agent_confirm "Agent wants to execute test script: $path" || { printf 'DENIED: user declined test execution.\n'; return 2; }
            (cd "$WORKSPACE" && bash "$abs" 2>&1) | agent_cap
            ;;
        *) printf 'ERROR: unsupported check: %s\n' "$check"; return 1 ;;
    esac
}

agent_tool_execute() {
    local tool="$1" args="$2"
    case "$tool" in
        list_files) agent_tool_list_files "$(jq -r '.path // "."' <<< "$args")" "$(jq -r '.depth // 2' <<< "$args")" ;;
        read_file) agent_tool_read_file "$(jq -r '.path // empty' <<< "$args")" "$(jq -r '.start_line // 1' <<< "$args")" "$(jq -r '.end_line // 0' <<< "$args")" ;;
        search_files) agent_tool_search_files "$(jq -r '.query // empty' <<< "$args")" "$(jq -r '.path // "."' <<< "$args")" ;;
        write_file) agent_tool_write_file "$(jq -r '.path // empty' <<< "$args")" "$(jq -r '.content // empty' <<< "$args")" ;;
        replace_text) agent_tool_replace_text "$(jq -r '.path // empty' <<< "$args")" "$(jq -r '.old // empty' <<< "$args")" "$(jq -r '.new // empty' <<< "$args")" ;;
        make_directory) agent_tool_make_directory "$(jq -r '.path // empty' <<< "$args")" ;;
        run_check) agent_tool_run_check "$(jq -r '.check // empty' <<< "$args")" "$(jq -r '.path // empty' <<< "$args")" ;;
        *) printf 'ERROR: unknown tool: %s\n' "$tool"; return 1 ;;
    esac
}

TOOLS='- list_files(path=".", depth=2): list workspace files. Read-only.
- read_file(path, start_line=1, end_line=0): read a text-file range. Read-only. .env, .git, .ssh and symlinks are blocked.
- search_files(query, path="."): search text within the workspace. Read-only.
- write_file(path, content): create or fully replace a text file. Requires user confirmation by default.
- replace_text(path, old, new): exact literal replacement. Requires confirmation.
- make_directory(path): create a directory. Requires confirmation.
- run_check(check, path=""): allowed checks are git_status, git_diff, git_diff_check, bash_n, jq, shellcheck, test_script. test_script is restricted to tests/ and requires confirmation.'

SYSTEM="You are Coral 1.6 Agent, Akro's small tool-use model. Complete the user's task by inspecting the workspace, making only necessary changes, checking your work, and stopping when the task is actually complete.

You operate through a strict action protocol. Every response MUST be one JSON object matching the schema Akro provides.

For an action, return:
{\"type\":\"tool\",\"tool\":\"tool_name\",\"arguments\":{...},\"response\":\"\"}

When finished, return:
{\"type\":\"final\",\"tool\":\"\",\"arguments\":{},\"response\":\"concise useful final summary\"}

Rules:
- Use tools instead of guessing about files or repository state.
- Make one useful tool call at a time.
- Read before editing.
- Stay inside the provided workspace.
- Never request .env, .git, .ssh, secrets, credentials, or paths outside the workspace.
- Prefer the smallest reliable change.
- Do not repeat a failed action without changing your approach.
- Verify meaningful code changes before finishing.
- Never claim a test passed unless its tool result says it passed.
- Do not ask the user to perform work that an available tool can do.
- Writes may require user confirmation. If a write is denied, adapt or finish without it.
- Do not output markdown outside the response field. Akro will render the final response.

AVAILABLE TOOLS:
$TOOLS"

CONTEXT="$(agent_context | head -c "${AGENT_CONTEXT_MAX_CHARS:-2200}")"
USER_MESSAGE="WORKSPACE: $WORKSPACE

TASK:
$TASK"
if [[ -n "$CONTEXT" ]]; then USER_MESSAGE="$USER_MESSAGE

SMALL RELEVANT AKRO CONTEXT:
$CONTEXT"; fi

MESSAGES="$(jq -nc --arg system "$SYSTEM" --arg user "$USER_MESSAGE" '[{role:"system",content:$system},{role:"user",content:$user}]')"
SCHEMA='{"type":"object","properties":{"type":{"type":"string","enum":["tool","final"]},"tool":{"type":"string"},"arguments":{"type":"object"},"response":{"type":"string"}},"required":["type","tool","arguments","response"],"additionalProperties":false}'

agent_call() {
    local out="$1" err="$2" payload="" pid=0 rc=0
    payload="$(jq -n --arg model "$AGENT_MODEL" --argjson messages "$MESSAGES" --argjson schema "$SCHEMA" --argjson ctx "$AGENT_NUM_CTX" --argjson predict "$AGENT_NUM_PREDICT" '{model:$model,messages:$messages,stream:false,think:false,format:$schema,keep_alive:"5m",options:{temperature:0.15,top_k:20,top_p:0.85,repeat_penalty:1.05,num_ctx:$ctx,num_predict:$predict}}')"
    curl -sS --connect-timeout 10 --max-time 300 -H 'Content-Type: application/json' -d "$payload" "$OLLAMA_CHAT_URL" > "$out" 2> "$err" &
    pid=$!
    ACTIVE_AGENT_PID=$pid
    agent_spin_wait "$pid" "agent thinking" || rc=$?
    ACTIVE_AGENT_PID=0
    return "$rc"
}

agent_notice "[agent: ${AGENT_MODEL%:latest} · workspace: $WORKSPACE]"

step=1 last_signature="" repeat_count=0 final_response="" changed=0
while (( step <= ${AGENT_MAX_STEPS:-20} )); do
    response_tmp="$(mktemp "$AKRO_RUNTIME_DIR/agent-response.XXXXXX")"
    error_tmp="$(mktemp "$AKRO_RUNTIME_DIR/agent-error.XXXXXX")"
    if ! agent_call "$response_tmp" "$error_tmp"; then
        err="$(cat "$error_tmp")"; rm -f "$response_tmp" "$error_tmp"
        printf 'Agent model request failed: %s\n' "$err" >&2; exit 1
    fi
    api_error="$(jq -r '.error // empty' "$response_tmp" 2>/dev/null || true)"
    [[ -z "$api_error" ]] || { rm -f "$response_tmp" "$error_tmp"; printf 'Agent model request failed: %s\n' "$api_error" >&2; exit 1; }
    content="$(jq -r '.message.content // empty' "$response_tmp" 2>/dev/null || true)"
    rm -f "$response_tmp" "$error_tmp"
    if ! jq -e 'type=="object" and (.type=="tool" or .type=="final") and (.tool|type=="string") and (.arguments|type=="object") and (.response|type=="string")' <<< "$content" >/dev/null 2>&1; then
        MESSAGES="$(jq -c --arg bad "$content" '. + [{role:"assistant",content:$bad},{role:"user",content:"Your last response did not match the required JSON action schema. Return exactly one valid action object."}]' <<< "$MESSAGES")"
        step=$((step + 1)); continue
    fi

    type="$(jq -r '.type' <<< "$content")"
    if [[ "$type" == "final" ]]; then
        final_response="$(jq -r '.response' <<< "$content")"
        agent_log "$(jq -nc --arg time "$(akro_timestamp)" --arg response "$final_response" '{event:"final",time:$time,response:$response}')"
        break
    fi

    tool="$(jq -r '.tool' <<< "$content")"
    args="$(jq -c '.arguments' <<< "$content")"
    signature="$tool:$args"
    if [[ "$signature" == "$last_signature" ]]; then repeat_count=$((repeat_count + 1)); else repeat_count=0; fi
    last_signature="$signature"

    if (( repeat_count >= ${AGENT_REPEAT_LIMIT:-2} )); then
        tool_result="ERROR: repeated identical action blocked. Change approach instead of retrying the same call."
        tool_rc=1
    else
        summary="$tool"
        p="$(jq -r '.path // empty' <<< "$args")"; [[ -z "$p" ]] || summary="$summary $p"
        q="$(jq -r '.query // empty' <<< "$args")"; [[ -z "$q" ]] || summary="$summary \"$q\""
        agent_notice "[tool: $summary]"
        tool_rc=0
        tool_result="$(agent_tool_execute "$tool" "$args" 2>&1)" || tool_rc=$?
        case "$tool" in write_file|replace_text|make_directory) (( tool_rc == 0 )) && changed=$((changed + 1)) ;; esac
    fi
    tool_result="$(printf '%s' "$tool_result" | head -c "${AGENT_MAX_TOOL_OUTPUT:-12000}")"
    preview="$(printf '%s' "$tool_result" | tr '\n\r\t' '   ' | cut -c1-300)"
    agent_log "$(jq -nc --arg time "$(akro_timestamp)" --arg tool "$tool" --argjson arguments "$args" --argjson rc "$tool_rc" --arg preview "$preview" '{event:"tool",time:$time,tool:$tool,arguments:$arguments,rc:$rc,result_preview:$preview}')"

    feedback="TOOL RESULT\nTool: $tool\nStatus: $([[ $tool_rc -eq 0 ]] && printf success || printf error)\nOutput:\n$tool_result"
    MESSAGES="$(jq -c --arg assistant "$content" --arg feedback "$feedback" '. + [{role:"assistant",content:$assistant},{role:"user",content:$feedback}]' <<< "$MESSAGES")"
    step=$((step + 1))
done

if [[ -z "$final_response" ]]; then
    MESSAGES="$(jq -c '. + [{role:"user",content:"The tool-step limit has been reached. Do not request another tool. Return a final action now that honestly summarizes what was completed, what was verified, and anything unresolved."}]' <<< "$MESSAGES")"
    response_tmp="$(mktemp "$AKRO_RUNTIME_DIR/agent-final.XXXXXX")"; error_tmp="$(mktemp "$AKRO_RUNTIME_DIR/agent-final-err.XXXXXX")"
    if agent_call "$response_tmp" "$error_tmp"; then
        content="$(jq -r '.message.content // empty' "$response_tmp" 2>/dev/null || true)"
        if jq -e '.type=="final" and (.response|type=="string")' <<< "$content" >/dev/null 2>&1; then final_response="$(jq -r '.response' <<< "$content")"; fi
    fi
    rm -f "$response_tmp" "$error_tmp"
fi

[[ -n "$(akro_trim "$final_response")" ]] || final_response="Agentic stopped after ${AGENT_MAX_STEPS:-20} steps without a clean final response. Review the run log at $LOG_FILE before trusting the workspace state."

jq -n --arg response "$final_response" --arg model "$AGENT_MODEL" --arg notice "Agentic completed. Run log: $LOG_FILE" '{complete:true,response:$response,model:$model,notice:$notice}'
