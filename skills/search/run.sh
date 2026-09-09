#!/usr/bin/env bash
set -uo pipefail
prompt="$(cat)"
if [[ -z "${TAVILY_API_KEY:-}" ]]; then printf 'TAVILY_API_KEY is not set.\n' >&2; exit 1; fi
[[ -n "$prompt" ]] || { printf 'Give /search a question to search for.\n' >&2; exit 1; }
today="$(date '+%B %d, %Y')"
payload="$(jq -n --arg query "$prompt\n\nCurrent date: $today" --argjson max "${TAVILY_MAX_RESULTS:-5}" '{query:$query,search_depth:"advanced",max_results:$max,include_answer:"advanced"}')"
response="$(curl -sS --connect-timeout 10 --max-time 45 -H "Authorization: Bearer $TAVILY_API_KEY" -H 'Content-Type: application/json' -d "$payload" "${TAVILY_API_URL:-https://api.tavily.com/search}")" || exit 1
api_error="$(jq -r '.error // empty' <<< "$response" 2>/dev/null || true)"; [[ -z "$api_error" ]] || { printf '%s\n' "$api_error" >&2; exit 1; }
results="$(jq -r '(if (.answer//"")!="" then "Search summary:\n"+.answer+"\n\n" else "" end)+"Search results:\n"+(.results|to_entries|map("\n["+((.key+1)|tostring)+"] "+(.value.title//"Untitled")+"\nURL: "+(.value.url//"")+"\nContent: "+((.value.content//"")|gsub("[\\r\\n\\t]+";" ")|.[0:1800]))|join("\n"))' <<< "$response")"
transformed="A current web search has already been completed. Answer from the supplied results. Use bracketed source numbers such as [1]. Do not invent sources.\n\n--- BEGIN SEARCH RESULTS ---\n$results\n--- END SEARCH RESULTS ---\n\nUSER REQUEST:\n$prompt"
jq -n --arg prompt "$transformed" --arg notice "Search complete: $(jq '.results|length' <<< "$response") result(s)." '{prompt:$prompt,notice:$notice}'
