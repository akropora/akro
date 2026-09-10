#!/usr/bin/env bash
set -uo pipefail
source "$AKRO_ROOT/config.sh"
source "$AKRO_ROOT/lib/common.sh"
source "$AKRO_ROOT/lib/ollama.sh"
source "$AKRO_ROOT/lib/projects.sh"
source "$AKRO_ROOT/lib/knowledge.sh"
source "$AKRO_ROOT/lib/brain.sh"

prompt="$(cat)"
[[ -n "$(akro_trim "$prompt")" ]] || { printf 'Give /promptup a request to improve.\n' >&2; exit 1; }
ollama_model_exists "$PROMPT_MODEL" || { printf 'Prompt model is not installed: %s\n' "$PROMPT_MODEL" >&2; exit 1; }

context=""
if ! project_is_isolated; then
    g="$(brain_context_scope "$AKRO_GLOBAL_DIR" GLOBAL "$prompt" 1 2>/dev/null || true)"
    p="$(brain_context_scope "$CURRENT_PROJECT_DIR" PROJECT "$prompt" 1 2>/dev/null || true)"
    context="$(printf '%s\n%s' "$g" "$p" | head -c "$PROMPTUP_CONTEXT_MAX_CHARS")"
fi

system='You are Coral 1.6 Prompt, a tiny prompt-refinement model for Akro. Rewrite the user request into a stronger prompt for another language model. Preserve the real goal and every explicit constraint. Add only useful structure, context, success criteria, and output requirements that are supported by the request or supplied context. Resolve harmless ambiguity when reasonable. Do not invent facts, preferences, requirements, sources, or actions. Do not answer the task. Do not mention that you are rewriting it. Keep easy prompts compact and make complex prompts detailed enough to guide a small model well. Return only the improved prompt.'

user="$prompt"
if [[ -n "$context" ]]; then
    user="Relevant background, use only if it helps disambiguate the request:\n---\n$context\n---\n\nREQUEST TO IMPROVE:\n$prompt"
fi
payload="$(jq -n --arg model "$PROMPT_MODEL" --arg system "$system" --arg user "$user" '{model:$model,messages:[{role:"system",content:$system},{role:"user",content:$user}],stream:false,think:false,keep_alive:"5m",options:{temperature:0.2,top_k:20,top_p:0.85,num_ctx:4096,num_predict:900,repeat_penalty:1.03}}')"
response="$(curl -sS --connect-timeout 10 --max-time 180 -H 'Content-Type: application/json' -d "$payload" "$OLLAMA_CHAT_URL")" || { printf 'Prompt model request failed.\n' >&2; exit 1; }
err="$(jq -r '.error // empty' <<< "$response" 2>/dev/null || true)"
[[ -z "$err" ]] || { printf '%s\n' "$err" >&2; exit 1; }
enhanced="$(jq -r '.message.content // empty' <<< "$response" 2>/dev/null || true)"
[[ -n "$(akro_trim "$enhanced")" ]] || { printf 'Prompt model returned an empty prompt.\n' >&2; exit 1; }
jq -n --arg prompt "$enhanced" --arg notice "Prompt enhanced with $PROMPT_MODEL." '{prompt:$prompt,notice:$notice}'
