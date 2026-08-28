#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AKRO_HOME="${AKRO_HOME:-$SCRIPT_DIR}"
CONFIG="$AKRO_HOME/.config"
SKILLS="$AKRO_HOME/skills.json"
CHATS="$AKRO_HOME/conversations"
OLLAMA="http://127.0.0.1:11434"
NEURON="neuron"

dot_cycle=('⠾' '⠽' '⠻' '⠟' '⠯' '⠟' '⠻' '⠽')

BLUE=$'\033[38;5;75m'
CYAN=$'\033[38;5;81m'
GREEN=$'\033[38;5;114m'
YELLOW=$'\033[38;5;221m'
RED=$'\033[38;5;203m'
GRAY=$'\033[38;5;244m'
DIM=$'\033[2m'
RESET=$'\033[0m'

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
    -d "$(jq -nc --arg model "$NEURON" --arg prompt "$prompt" '{model:$model,stream:false,prompt:("/no_think\nCreate a short 2-5 word title for this chat.\nReturn ONLY the title words.\nDo not write "Title", "Chat", quotes, punctuation, or an explanation.\nUser message:\n\n"+$prompt)}')" \
    2>/dev/null || true)

  name=$(printf '%s' "$response" | jq -r '.response // empty' | tr '\n' ' ' | sed 's/^[[:space:]"'"'']*//; s/[[:space:]"'"'']*$//')
  [ -n "$name" ] || name="New Chat"

  title="$name"
  title=$(printf '%s' "$title" | sed -E 's/^(title|chat)[[:space:]:-]+//I')
  slug=$(slugify "$title")
  [ -n "$slug" ] || slug="chat"
  file="$CHATS/$slug.json"

  if [ -e "$file" ]; then
    file="$CHATS/$slug-$(date '+%Y%m%d-%H%M%S').json"
  fi

  printf '%sSaved as: %s%s\n' "$GREEN" "$(basename "$file" .json)" "$RESET"
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
  printf '%s%s%s\n' "$CYAN" "$title" "$RESET"
  printf '%s%s%s\n\n' "$GRAY" "$current_model" "$RESET"
  echo
}

spinner() {
  local pid="$1" i=0
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s' "$GRAY" "${dot_cycle[$i]}" "$RESET"
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
    printf '%sOllama request failed.%s\n' "$RED" "$RESET"
    return
  fi

  response=$(cat "$tmp")
  rm -f "$tmp"
  answer=$(printf '%s' "$response" | jq -r '.message.content // empty')

  [ -n "$answer" ] || {
    printf '%sOllama returned an empty response.%s\n' "$RED" "$RESET"
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
  printf '%s%s%s\n\n' "$GRAY" "$current_model" "$RESET"
  echo
fi

trap 'printf "\033[?25h"; save_chat; exit 130' INT TERM
trap 'printf "\033[?25h"' EXIT

while true; do
  printf '%s> ' "$BLUE"
  IFS= read -e -r input || break
  printf '%s' "$RESET"
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
      printf '%s%s%s\n' "$CYAN" "$current_model" "$RESET"
      continue
      ;;
    /model\ *)
      next_model="${input#/model }"
      if ollama show "$next_model" >/dev/null 2>&1; then
        printf '%s%s%s\n' "$CYAN" "$current_model" "$RESET"
        save_chat
        echo "$current_model"
      else
        printf '%sModel not found: %s%s\n' "$YELLOW" "$next_model" "$RESET"
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
      printf '%sUnknown command or skill: %s%s\n' "$YELLOW" "$skill" "$RESET"
      continue
    fi
  fi

  if [ -z "$file" ]; then
    name_chat "$user_text"
  fi

  ask_model "$user_text" "$send_text"
  echo
done
