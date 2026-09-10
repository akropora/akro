#!/usr/bin/env bash

ESC="$(printf '\033')"
ORANGE='\033[38;5;208m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[31m'
WHITE='\033[0;97m'
GRAY='\033[0;90m'
RESET='\033[0m'

MENU_SELECTED=0
MENU_COUNT=0
PICKER_RESULT=-1
PICKER_ALLOW_DELETE=false
MENU_ITEMS=()
MENU_LABELS=()

ui_cleanup() {
    printf '%b' "$RESET"
    tput cnorm 2>/dev/null || true
    stty sane 2>/dev/null || true
}

ui_notice() {
    local text="$1"
    local color="${2:-$GRAY}"
    [[ -n "$text" ]] || return 0
    printf '%b%s%b\n\n' "$color" "$text" "$RESET"
}

ui_render_markdown() {
    local content="$1"
    local width=80
    [[ -n "$content" ]] || return 0
    width="$(tput cols 2>/dev/null || printf '80')"
    (( width > 4 )) && width=$((width - 2))
    if command -v glow >/dev/null 2>&1; then printf '%s\n' "$content" | glow -w "$width" -; else printf '%s\n' "$content"; fi
}

ui_repeat_char() {
    local char="$1" count="$2" out="" i=0
    for ((i=0; i<count; i++)); do out+="$char"; done
    printf '%s' "$out"
}

ui_format_count() {
    local count="${1:-0}"
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    if (( count >= 1000000 )); then awk -v c="$count" 'BEGIN{printf "%.2fM",c/1000000}'
    elif (( count >= 1000 )); then awk -v c="$count" 'BEGIN{printf "%.1fK",c/1000}'
    else printf '%s' "$count"; fi
}

ui_context_bar() {
    local used="${1:-0}" max="${CHAT_NUM_CTX:-16384}" width=20 pct=0 filled=0 empty=0
    case "$used" in ''|*[!0-9]*) used=0 ;; esac
    case "$max" in ''|*[!0-9]*) max=16384 ;; esac
    (( max < 1 )) && max=16384
    pct=$((used * 100 / max)); (( pct > 100 )) && pct=100
    filled=$((used * width / max)); (( filled > width )) && filled=$width
    empty=$((width - filled))
    printf '['
    printf '%b%s%b' "$GREEN" "$(ui_repeat_char '#' "$filled")" "$RESET"
    printf '%b%s%b' "$GRAY" "$(ui_repeat_char '.' "$empty")" "$RESET"
    printf '] %s / %s (%s%%)' "$(ui_format_count "$used")" "$(ui_format_count "$max")" "$pct"
}

ui_activity_wait() {
    local pid="$1"
    local label="${2:-working}"
    local frame=0 spinner=""
    local -a cycle=('|' '/' '-' '\\')
    [[ "${AKRO_SHOW_ACTIVITY:-1}" == "1" ]] || { wait "$pid"; return $?; }
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        spinner="${cycle[$((frame % ${#cycle[@]}))]}"
        printf '\r%b[%s %s...]%b' "$GRAY" "$spinner" "$label" "$RESET"
        frame=$((frame+1))
        sleep 0.10
    done
    local rc=0
    wait "$pid" || rc=$?
    printf '\r\033[2K'
    tput cnorm 2>/dev/null || true
    return "$rc"
}

ui_draw_picker() {
    local title="$1" subtitle="${2:-}" i=0 rows=24 max_visible=10 start=0 end=0
    rows="$(tput lines 2>/dev/null || printf '24')"
    max_visible=$((rows - 8)); (( max_visible < 5 )) && max_visible=5
    if (( MENU_SELECTED >= max_visible )); then start=$((MENU_SELECTED-max_visible+1)); fi
    end=$((start+max_visible)); (( end > MENU_COUNT )) && end=$MENU_COUNT
    printf '\033[2J\033[H'
    printf '%b%s%b\n' "$WHITE" "$title" "$RESET"
    [[ -n "$subtitle" ]] && printf '%b%s%b\n' "$GRAY" "$subtitle" "$RESET"
    printf '\n'
    for ((i=start; i<end; i++)); do
        if (( i == MENU_SELECTED )); then printf '%b> %s%b\n' "$BLUE" "${MENU_LABELS[$i]}" "$RESET"; else printf '  %s\n' "${MENU_LABELS[$i]}"; fi
    done
    printf '\n%b↑ ↓ move   Enter select   Esc cancel%b' "$GRAY" "$RESET"
    [[ "$PICKER_ALLOW_DELETE" == true ]] && printf '   %bD delete%b' "$GRAY" "$RESET"
}

ui_picker() {
    local title="$1" subtitle="${2:-}" allow_delete="${3:-false}" old_stty="" key="" k2="" k3=""
    MENU_SELECTED=0; MENU_COUNT=${#MENU_ITEMS[@]}; PICKER_RESULT=-1; PICKER_ALLOW_DELETE="$allow_delete"
    (( MENU_COUNT > 0 )) || return 1
    old_stty="$(stty -g)"
    stty -echo -icanon min 1 time 0 -ixon
    tput civis
    ui_draw_picker "$title" "$subtitle"
    while true; do
        IFS= read -rsn1 key || { stty "$old_stty"; tput cnorm; return 1; }
        case "$key" in
            '') PICKER_RESULT=$MENU_SELECTED; stty "$old_stty"; tput cnorm; return 0 ;;
            d|D)
                if [[ "$allow_delete" == true ]]; then PICKER_RESULT=$MENU_SELECTED; stty "$old_stty"; tput cnorm; return 2; fi
                ;;
            "$ESC")
                if ! IFS= read -rsn1 -t 1 k2; then stty "$old_stty"; tput cnorm; return 1; fi
                if [[ "$k2" == "[" ]]; then
                    IFS= read -rsn1 -t 1 k3 || true
                    case "$k3" in
                        A) MENU_SELECTED=$((MENU_SELECTED-1)); (( MENU_SELECTED < 0 )) && MENU_SELECTED=$((MENU_COUNT-1)) ;;
                        B) MENU_SELECTED=$((MENU_SELECTED+1)); (( MENU_SELECTED >= MENU_COUNT )) && MENU_SELECTED=0 ;;
                    esac
                else stty "$old_stty"; tput cnorm; return 1; fi
                ;;
        esac
        ui_draw_picker "$title" "$subtitle"
    done
}


ui_background_status() {
    local status_file="$AKRO_RUNTIME_DIR/remember/status" status="" seen_file="$AKRO_RUNTIME_DIR/remember/status.seen"
    [[ -f "$status_file" ]] || return 0
    status="$(cat "$status_file" 2>/dev/null || true)"
    [[ -n "$status" ]] || return 0
    if [[ ! -f "$seen_file" || "$(cat "$seen_file" 2>/dev/null || true)" != "$status" ]]; then
        case "$status" in
            remembered:*) printf '%b[ok remembered]%b\n\n' "$GRAY" "$RESET" ;;
            failed:*) printf '%b[! remembering failed: %s]%b\n\n' "$YELLOW" "${status#failed:}" "$RESET" ;;
        esac
        printf '%s' "$status" > "$seen_file"
    fi
}
