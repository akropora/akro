#!/usr/bin/env bash

akro_timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }
akro_epoch() { date '+%s'; }

akro_trim() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

akro_slug() {
    local value="${1-}"
    local slug=""
    slug="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//')"
    [[ -n "$slug" ]] || slug="untitled"
    printf '%s' "$slug"
}

akro_expand_path() {
    local path="${1-}"
    case "$path" in
        "~") printf '%s' "$HOME" ;;
        "~/"*) printf '%s/%s' "$HOME" "${path#\~/}" ;;
        *) printf '%s' "$path" ;;
    esac
}

akro_absolute_path() {
    local path=""
    local dir=""
    local base=""
    path="$(akro_expand_path "$1")"
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s' "$dir" "$base"
}

akro_file_size() {
    local path="$1"
    if stat -f '%z' "$path" >/dev/null 2>&1; then stat -f '%z' "$path"; else stat -c '%s' "$path"; fi
}

akro_fingerprint() {
    cksum "$1" 2>/dev/null | awk '{print $1 ":" $2}'
}

akro_require_commands() {
    local c=""
    for c in bash curl jq awk sed grep cksum mktemp tput stty; do
        command -v "$c" >/dev/null 2>&1 || { printf 'Required command not found: %s\n' "$c" >&2; return 1; }
    done
}

akro_json_file_init() {
    local path="$1"
    local initial="$2"
    mkdir -p "$(dirname "$path")"
    [[ -f "$path" ]] || printf '%s\n' "$initial" > "$path"
}

akro_atomic_write() {
    local destination="$1"
    local temp=""
    temp="$(mktemp "$(dirname "$destination")/.tmp.XXXXXX")" || return 1
    cat > "$temp"
    mv "$temp" "$destination"
}

akro_query_words() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -cs '[:alnum:]' '\n' |
        awk '
            BEGIN {
                split("the a an and or but if then than this that these those to of for from in on at with without about into by as is are was were be been being do does did can could would should will have has had i me my mine we our ours you your yours what who when where why how tell show give explain describe find search use based current currently just really thing things something anything note notes document documents file files chat chats conversation conversations", w, " ")
                for (i in w) stop[w[i]]=1
            }
            ($0 == "ai" || length($0) >= 3) && !stop[$0] && !seen[$0]++
        '
}
