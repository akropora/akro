#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AKRO_HOME="${AKRO_HOME:-$SCRIPT_DIR}"
CONFIG="$AKRO_HOME/.config"
SKILLS="$AKRO_HOME/skills.json"
CHATS="$AKRO_HOME/conversations"
OLLAMA="http://127.0.0.1:11434"
NEURON="neuron"

dot_cycle=('⠾' '⠽' '⠻' '⠟' '⠯' '⠟' '⠻' '⠽')

mkdir -p "$CHATS"

help() {
  cat <<EOF_HELP
Akro

Usage:
  akro                    Start a new chat
  akro list               List saved chats
  akro open <name>        Open a saved chat
  akro help               Show this help

In chat:
  /skills                 List prompt skills
  /model                   Show the current model
  /model <name>            Switch models
  /new                     Start a new chat
  /exit | /bye | /quit     Save and exit

Files:
  $CONFIG
  $SKILLS
  $AKRO_HOME/modelfiles/
  $CHATS/
EOF_HELP
}

list_chats() {
  find "$CHATS" -maxdepth 1 -type f -name '*.json' -print 2>/dev/null \
    | sed 's#.*/##; s/\.json$//' \
    | sort
}

case "${1:-}" in
  help|-h|--help)
    help
    exit
    ;;
  list)
    list_chats
    exit
    ;;
esac

for cmd in curl jq glow ollama; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd"
    exit 1
  }
done

[ -f "$CONFIG" ] || {
  echo "Missing $CONFIG. Run install.sh first."
  exit 1
}

# shellcheck disable=SC1090
. "$CONFIG"
[ -n "${MODEL:-}" ] || {
  echo "MODEL is not set in $CONFIG"
  exit 1
}

curl -fsS "$OLLAMA/api/tags" >/dev/null 2>&1 || {
  echo "Ollama is not running at $OLLAMA"
  exit 1
}

current_model="$MODEL"
title=""
file=""
messages='[]'

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alnum:]' '-' \
    | sed 's/^-*//; s/-*$//; s/--*/-/g' \
    | cut -c1-60
}

save_chat() {
  [ -n "$file" ] || return
  jq -n \
    --arg title "$title" \
    --arg model "$current_model" \
    --argjson messages "$messages" \
    '{title:$title, model:$model, messages:$messages}' > "$file.tmp" && mv "$file.tmp" "$file"
}

name_chat() {
  local prompt="$1" response name slug
  response=$(curl -fsS "$OLLAMA/api/generate" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg model "$NEURON" --arg prompt "$prompt" '{model:$model,stream:false,prompt:("/no_think\nName this chat in 3 to 7 words. Return only the title.\n\n"+$prompt)}')" \
    2>/dev/null || true)

  name=$(printf '%s' "$response" | jq -r '.response // empty' | tr '\n' ' ' | sed 's/^[[:space:]"'"'']*//; s/[[:space:]"'"'']*$//')
  [ -n "$name" ] || name="New Chat"

  title="$name"
  slug=$(slugify "$name")
  [ -n "$slug" ] || slug="chat"
  file="$CHATS/$slug.json"

  if [ -e "$file" ]; then
    file="$CHATS/$slug-$(date '+%Y%m%d-%H%M%S').json"
  fi

  echo "Saved as: $(basename "$file" .json)"
}

open_chat() {
  local path
  path="$CHATS/${1%.json}.json"
  [ -f "$path" ] || {
    echo "Chat not found: ${1%.json}"
    exit 1
  }

  title=$(jq -r '.title // "Untitled"' "$path")
  current_model=$(jq -r '.model // empty' "$path")
  messages=$(jq -c '.messages // []' "$path")
  file="$path"

  [ -n "$current_model" ] || current_model="$MODEL"
  echo "$title"
  echo "$current_model"
  echo
}

spinner() {
  local pid="$1" i=0
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s' "${dot_cycle[$i]}"
    i=$(( (i + 1) % ${#dot_cycle[@]} ))
    sleep 0.09
  done
  printf '\r\033[K\033[?25h'
}

ask_model() {
  local user_text="$1" send_text="$2" request response answer tmp pid status
  request=$(jq -nc \
    --arg model "$current_model" \
    --argjson old "$messages" \
    --arg text "$send_text" \
    '{model:$model,stream:false,messages:($old + [{role:"user",content:$text}])}')

  tmp=$(mktemp)
  curl -fsS "$OLLAMA/api/chat" \
    -H 'Content-Type: application/json' \
    -d "$request" > "$tmp" 2>/dev/null &
  pid=$!
  spinner "$pid"
  wait "$pid"
  status=$?

  if [ "$status" -ne 0 ]; then
    rm -f "$tmp"
    echo "Ollama request failed."
    return
  fi

  response=$(cat "$tmp")
  rm -f "$tmp"
  answer=$(printf '%s' "$response" | jq -r '.message.content // empty')

  [ -n "$answer" ] || {
    echo "Ollama returned an empty response."
    return
  }

  messages=$(printf '%s' "$messages" | jq -c \
    --arg user "$user_text" \
    --arg assistant "$answer" \
    '. + [{role:"user",content:$user},{role:"assistant",content:$assistant}]')

  printf '%s\n' "$answer" | glow -
  save_chat
}

show_skills() {
  jq -r 'keys[] | "/" + .' "$SKILLS" 2>/dev/null
}

new_chat() {
  save_chat
  title=""
  file=""
  messages='[]'
  current_model="$MODEL"
  echo
}

if [ "${1:-}" = "open" ]; then
  [ -n "${2:-}" ] || {
    echo "Usage: akro open <name>"
    exit 1
  }
  open_chat "$2"
elif [ -n "${1:-}" ]; then
  help
  exit 1
else
  echo "$current_model"
  echo
fi

trap 'printf "\033[?25h"; save_chat; exit 130' INT TERM
trap 'printf "\033[?25h"' EXIT

while true; do
  IFS= read -e -r -p '> ' input || break
  [ -n "$input" ] || continue

  case "$input" in
    /exit|/bye|/quit)
      save_chat
      break
      ;;
    /new)
      new_chat
      continue
      ;;
    /skills)
      show_skills
      continue
      ;;
    /model)
      echo "$current_model"
      continue
      ;;
    /model\ *)
      next_model="${input#/model }"
      if ollama show "$next_model" >/dev/null 2>&1; then
        current_model="$next_model"
        save_chat
        echo "$current_model"
      else
        echo "Model not found: $next_model"
      fi
      continue
      ;;
  esac

  user_text="$input"
  send_text="$input"

  if [[ "$input" == /* ]]; then
    skill="${input%% *}"
    skill_name="${skill#/}"
    instruction=$(jq -r --arg name "$skill_name" '.[$name] // empty' "$SKILLS" 2>/dev/null)

    if [ -n "$instruction" ]; then
      if [ "$input" = "$skill" ]; then
        echo "Usage: $skill <prompt>"
        continue
      fi
      user_text="${input#* }"
      send_text="$instruction

$user_text"
    else
      echo "Unknown command or skill: $skill"
      continue
    fi
  fi

  if [ -z "$file" ]; then
    name_chat "$user_text"
  fi

  ask_model "$user_text" "$send_text"
  echo
done
