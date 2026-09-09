#!/usr/bin/env bash

OLLAMA_ERROR=""
OLLAMA_RESULT=""
OLLAMA_LAST_RAW=""
OLLAMA_MODELS_CACHE=""
OLLAMA_EMBED_AVAILABLE_CACHE=""
OLLAMA_EMBED_CACHE_KEY=""
OLLAMA_EMBED_CACHE_VALUE=""

ollama_models_json() {
    local response=""
    if [[ -n "$OLLAMA_MODELS_CACHE" ]]; then printf '%s' "$OLLAMA_MODELS_CACHE"; return 0; fi
    response="$(curl -sS --connect-timeout 2 --max-time 8 "$OLLAMA_TAGS_URL" 2>/dev/null)" || return 1
    OLLAMA_MODELS_CACHE="$(jq -c '[.models[]?.name] | unique' <<< "$response" 2>/dev/null)" || return 1
    printf '%s' "$OLLAMA_MODELS_CACHE"
}

ollama_model_exists() {
    local model="$1" models=""
    models="$(ollama_models_json || true)"
    [[ -n "$models" ]] || return 1
    jq -e --arg model "$model" 'index($model) != null' <<< "$models" >/dev/null 2>&1
}

ollama_choose_default() {
    local models="" first=""
    models="$(ollama_models_json || true)"
    [[ -n "$models" && "$models" != "[]" ]] || return 1
    if jq -e --arg m "$DEFAULT_MODEL" 'index($m) != null' <<< "$models" >/dev/null 2>&1; then
        BASE_MODEL="$DEFAULT_MODEL"
        return 0
    fi
    first="$(jq -r '.[0] // empty' <<< "$models")"
    [[ -n "$first" ]] || return 1
    BASE_MODEL="$first"
}

ollama_call_json() {
    local model="$1" prompt="$2" max_predict="${3:-1600}" num_ctx="${4:-8192}" schema="${5:-}"
    local payload="" response="" content="" clean="" api_error="" attempt=1 retries="${BRAIN_JSON_RETRIES:-2}"
    OLLAMA_ERROR=""; OLLAMA_RESULT=""; OLLAMA_LAST_RAW=""
    case "$retries" in ''|*[!0-9]*) retries=2 ;; esac
    (( retries < 1 )) && retries=1
    while (( attempt <= retries )); do
        if [[ -n "$schema" ]]; then
            payload="$(jq -n --arg model "$model" --arg prompt "$prompt" --argjson max "$max_predict" --argjson ctx "$num_ctx" --argjson schema "$schema" '{model:$model,messages:[{role:"user",content:$prompt}],stream:false,think:false,format:$schema,keep_alive:"5m",options:{temperature:0,num_ctx:$ctx,num_predict:$max}}')"
        else
            payload="$(jq -n --arg model "$model" --arg prompt "$prompt" --argjson max "$max_predict" --argjson ctx "$num_ctx" '{model:$model,messages:[{role:"user",content:$prompt}],stream:false,think:false,format:"json",keep_alive:"5m",options:{temperature:0,num_ctx:$ctx,num_predict:$max}}')"
        fi
        if ! response="$(curl -sS --connect-timeout 10 --max-time 600 -H 'Content-Type: application/json' -d "$payload" "$OLLAMA_CHAT_URL" 2>&1)"; then
            OLLAMA_ERROR="$model request failed: $response"; return 1
        fi
        api_error="$(jq -r '.error // empty' <<< "$response" 2>/dev/null || true)"
        [[ -z "$api_error" ]] || { OLLAMA_ERROR="$model request failed: $api_error"; return 1; }
        content="$(jq -r '.message.content // empty' <<< "$response" 2>/dev/null || true)"
        OLLAMA_LAST_RAW="$content"
        if [[ -n "$content" ]] && jq -e 'type=="object"' <<< "$content" >/dev/null 2>&1; then OLLAMA_RESULT="$(jq -c '.' <<< "$content")"; return 0; fi
        clean="$(printf '%s\n' "$content" | sed '/^[[:space:]]*```json[[:space:]]*$/d; /^[[:space:]]*```[[:space:]]*$/d')"
        if [[ -n "$clean" ]] && jq -e 'type=="object"' <<< "$clean" >/dev/null 2>&1; then OLLAMA_RESULT="$(jq -c '.' <<< "$clean")"; return 0; fi
        attempt=$((attempt+1))
    done
    clean="$(printf '%s' "$OLLAMA_LAST_RAW" | tr '\n\r\t' '   ' | cut -c 1-180)"
    OLLAMA_ERROR="$model returned invalid JSON after $retries attempt(s)."
    [[ -z "$clean" ]] || OLLAMA_ERROR+=" Raw: $clean"
    return 1
}

ollama_embed_available() {
    [[ -n "${AKRO_EMBED_MODEL:-}" ]] || return 1
    if [[ "$OLLAMA_EMBED_AVAILABLE_CACHE" == yes ]]; then return 0; fi
    if [[ "$OLLAMA_EMBED_AVAILABLE_CACHE" == no ]]; then return 1; fi
    if ollama_model_exists "$AKRO_EMBED_MODEL"; then OLLAMA_EMBED_AVAILABLE_CACHE=yes; return 0; fi
    OLLAMA_EMBED_AVAILABLE_CACHE=no
    return 1
}

ollama_embed() {
    local text="$1" payload="" response="" api_error="" key=""
    OLLAMA_RESULT=""; OLLAMA_ERROR=""
    [[ -n "${AKRO_EMBED_MODEL:-}" ]] || return 1
    key="$(printf '%s' "$AKRO_EMBED_MODEL:$text" | cksum | awk '{print $1 ":" $2}')"
    if [[ "$key" == "$OLLAMA_EMBED_CACHE_KEY" && -n "$OLLAMA_EMBED_CACHE_VALUE" ]]; then OLLAMA_RESULT="$OLLAMA_EMBED_CACHE_VALUE"; return 0; fi
    payload="$(jq -n --arg model "$AKRO_EMBED_MODEL" --arg input "$text" '{model:$model,input:$input,truncate:true,keep_alive:"5m"}')"
    if ! response="$(curl -sS --connect-timeout 5 --max-time 120 -H 'Content-Type: application/json' -d "$payload" "$OLLAMA_EMBED_URL" 2>&1)"; then OLLAMA_ERROR="$response"; return 1; fi
    api_error="$(jq -r '.error // empty' <<< "$response" 2>/dev/null || true)"
    [[ -z "$api_error" ]] || { OLLAMA_ERROR="$api_error"; return 1; }
    OLLAMA_RESULT="$(jq -c '.embeddings[0] // empty' <<< "$response" 2>/dev/null || true)"
    [[ -n "$OLLAMA_RESULT" && "$OLLAMA_RESULT" != "null" ]] || return 1
    OLLAMA_EMBED_CACHE_KEY="$key"; OLLAMA_EMBED_CACHE_VALUE="$OLLAMA_RESULT"
}

ollama_stream_chat() {
    local model="$1" messages_json="$2" response_file="$3" error_file="$4"
    local payload="" line="" chunk="" thinking="" saw_content=0
    payload="$(jq -n --arg model "$model" --argjson messages "$messages_json" --argjson ctx "$CHAT_NUM_CTX" --argjson predict "$CHAT_NUM_PREDICT" '{model:$model,messages:$messages,stream:true,keep_alive:"10m",options:{num_ctx:$ctx,num_predict:$predict}}')"
    : > "$response_file"; : > "$error_file"
    printf '%b[thinking...]%b' "$GRAY" "$RESET"
    while IFS= read -r line; do
        printf '%s\n' "$line" >> "$response_file"
        chunk="$(jq -r '.message.content // empty' <<< "$line" 2>/dev/null || true)"
        thinking="$(jq -r '.message.thinking // empty' <<< "$line" 2>/dev/null || true)"
        if [[ -n "$thinking" && $saw_content -eq 0 ]]; then
            printf '\r%b[thinking...]%b' "$GRAY" "$RESET"
        fi
        if [[ -n "$chunk" ]]; then
            if (( saw_content == 0 )); then
                printf '\r\033[2K%b %s > %b' "$PURPLE" "${model%:latest}" "$RESET"
                saw_content=1
            fi
            printf '%s' "$chunk"
        fi
    done < <(curl -sS --connect-timeout 10 --max-time 600 -H 'Content-Type: application/json' -d "$payload" "$OLLAMA_CHAT_URL" 2> "$error_file")
    local rc=${PIPESTATUS[0]:-0}
    if (( saw_content == 0 )); then printf '\r\033[2K'; else printf '\n\n'; fi
    return "$rc"
}
