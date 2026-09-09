#!/usr/bin/env bash

command_help() {
    printf '%bCommands%b\n' "$WHITE" "$RESET"
    cat <<'TXT'
  /model             choose an installed Ollama model
  /chats             browse saved chats in the current project
  /new               start a new chat
  /save name         rename the current chat
  /project           switch projects
  /project name      switch to or create a project
  /memory            browse project and global Brain notes
  /learn             learn new or changed project sources
  /learn-all         rebuild project Brain notes
  /brain             show Brain and knowledge status
  /skills            show auto-detected skills
  /prompt            inspect the last prompt sent to the main model
  /CLEAR             clear current project's chats, docs, memory and knowledge
  /help or /?        show this help
  /quit              exit

Skills are suffix slash commands, for example:
  explain this /concise
  fix this code /plsfix
  latest Ollama release /search
  summarize this /document [~/notes/report.txt]

Enter """ by itself to start multiline input.
TXT
    printf '\n'
}

command_model_picker() {
    local models="" model="" idx=0
    models="$(ollama_models_json || true)"; [[ -n "$models" && "$models" != '[]' ]] || { ui_notice 'Could not read installed Ollama models.' "$RED"; return 1; }
    MENU_ITEMS=(); MENU_LABELS=()
    while IFS= read -r model; do
        [[ -n "$model" ]] || continue
        MENU_ITEMS+=("$model")
        if [[ "$model" == "$BASE_MODEL" ]]; then MENU_LABELS+=("${model%:latest}  ✓"); else MENU_LABELS+=("${model%:latest}"); fi
    done < <(jq -r '.[]' <<< "$models")
    if ui_picker 'Models' 'Installed Ollama models.'; then idx=$PICKER_RESULT; BASE_MODEL="${MENU_ITEMS[$idx]}"; chat_autosave; ui_redraw; ui_notice "Model: $BASE_MODEL" "$GREEN"; else ui_redraw; fi
}

command_chat_picker() {
    local file="" name="" model="" idx=0 rc=0
    while true; do
        MENU_ITEMS=(); MENU_LABELS=()
        for file in "$CURRENT_PROJECT_DIR/chats"/*.json; do
            [[ -f "$file" ]] || continue
            name="$(jq -r '.name // empty' "$file" 2>/dev/null || true)"; [[ -n "$name" ]] || name="$(basename "$file" .json)"
            model="$(jq -r '.model // "unknown"' "$file" 2>/dev/null || printf unknown)"
            MENU_ITEMS+=("$file"); MENU_LABELS+=("$name   [${model%:latest}]")
        done
        (( ${#MENU_ITEMS[@]} > 0 )) || { ui_redraw; ui_notice 'No chats in this project yet.' "$GRAY"; return 1; }
        if ui_picker "Chats · $CURRENT_PROJECT_NAME" 'Enter opens a conversation. D deletes it.' true; then
            idx=$PICKER_RESULT; chat_load "${MENU_ITEMS[$idx]}"; ui_redraw; return 0
        else
            rc=$?
            if (( rc == 2 )); then
                idx=$PICKER_RESULT; file="${MENU_ITEMS[$idx]}"
                [[ "$file" != "$CURRENT_CHAT_FILE" ]] || chat_new
                rm -f -- "$file"
                continue
            fi
            ui_redraw; return 1
        fi
    done
}
command_project_picker() {
    local slug="" name="" idx=0
    MENU_ITEMS=(); MENU_LABELS=()
    while IFS=$'\t' read -r slug name; do
        [[ -n "$slug" ]] || continue
        MENU_ITEMS+=("$slug")
        if [[ "$slug" == "$CURRENT_PROJECT_SLUG" ]]; then MENU_LABELS+=("$name  ✓"); else MENU_LABELS+=("$name"); fi
    done < <(project_list)
    if ui_picker 'Projects' 'Use /project name to create a new project.'; then
        idx=$PICKER_RESULT; chat_new; project_use "${MENU_ITEMS[$idx]}"; ui_redraw; ui_notice "Project: $CURRENT_PROJECT_NAME" "$GREEN"
    else ui_redraw; fi
}

command_save_chat() {
    local requested="$(akro_trim "$1")" dest=""
    [[ -n "$requested" ]] || { ui_notice 'Usage: /save name' "$GRAY"; return 1; }
    [[ -n "$CURRENT_CHAT_FILE" ]] || { ui_notice 'Send a message first.' "$GRAY"; return 1; }
    dest="$(dirname "$CURRENT_CHAT_FILE")/$(akro_slug "$requested").json"
    if [[ "$dest" != "$CURRENT_CHAT_FILE" && -e "$dest" ]]; then dest="$(chat_unique_path "$requested")"; fi
    [[ "$dest" == "$CURRENT_CHAT_FILE" ]] || { mv "$CURRENT_CHAT_FILE" "$dest"; CURRENT_CHAT_FILE="$dest"; }
    CURRENT_CHAT_NAME="$requested"; chat_write "$CURRENT_CHAT_FILE" "$CURRENT_CHAT_NAME"; ui_notice "Renamed: $CURRENT_CHAT_NAME" "$GREEN"
}

command_memory_picker() {
    local scope="" label="" note="" title="" type="" importance="" idx=0 choice="" selected="" selected_scope=""
    MENU_ITEMS=(); MENU_LABELS=()
    for scope in "$CURRENT_PROJECT_DIR" "$AKRO_GLOBAL_DIR"; do
        if [[ "$scope" == "$CURRENT_PROJECT_DIR" ]]; then label="project"; else label="global"; fi
        while IFS=$'\t' read -r note title type importance; do
            [[ -n "$note" ]] || continue
            MENU_ITEMS+=("$scope|$note"); MENU_LABELS+=("[$label] $title   $type · $importance")
        done < <(jq -r '.sources|to_entries[]?|[.value.note,.value.title,(.value.memory_type//"fact"),((.value.importance//0.5)|tostring)]|@tsv' "$scope/brain/index.json" 2>/dev/null)
    done
    (( ${#MENU_ITEMS[@]} > 0 )) || { ui_notice 'No Brain memories yet. Run /learn after chatting.' "$GRAY"; return 1; }
    if ! ui_picker 'Memory' 'Enter inspects a note.'; then ui_redraw; return 1; fi
    idx=$PICKER_RESULT; selected="${MENU_ITEMS[$idx]}"; selected_scope="${selected%%|*}"; note="${selected#*|}"
    printf '\033[2J\033[H'; ui_render_markdown "$(cat "$selected_scope/brain/notes/$note")"
    printf '\n%bE edit   D delete' "$GRAY"
    [[ "$selected_scope" == "$CURRENT_PROJECT_DIR" ]] && printf '   G make global'
    printf '   Enter back%b\n' "$RESET"
    local action_notice=""
    IFS= read -rsn1 choice || true
    case "$choice" in
        e|E) "${EDITOR:-vi}" "$selected_scope/brain/notes/$note"; brain_refresh_note_index "$selected_scope" "$note" || true ;;
        d|D) brain_delete_note "$selected_scope" "$note"; action_notice='Memory deleted.' ;;
        g|G) if [[ "$selected_scope" == "$CURRENT_PROJECT_DIR" ]] && brain_promote_note "$selected_scope" "$note"; then action_notice='Memory copied to global Brain.'; fi ;;
    esac
    ui_redraw
    [[ -z "$action_notice" ]] || ui_notice "$action_notice" "$GREEN"
}

command_brain_status() {
    local pnotes=0 gnotes=0 pchunks=0 gchunks=0 docs=0 chats=0 embed='keyword only'
    pnotes="$(jq '.sources|length' "$CURRENT_PROJECT_DIR/brain/index.json" 2>/dev/null || printf 0)"; gnotes="$(jq '.sources|length' "$AKRO_GLOBAL_DIR/brain/index.json" 2>/dev/null || printf 0)"
    pchunks="$(jq '.chunks|length' "$CURRENT_PROJECT_DIR/knowledge/index.json" 2>/dev/null || printf 0)"; gchunks="$(jq '.chunks|length' "$AKRO_GLOBAL_DIR/knowledge/index.json" 2>/dev/null || printf 0)"
    docs="$(find "$CURRENT_PROJECT_DIR/documents" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"; chats="$(find "$CURRENT_PROJECT_DIR/chats" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
    ollama_embed_available && embed="$AKRO_EMBED_MODEL"
    printf '%bBrain · %s%b\n\n' "$WHITE" "$CURRENT_PROJECT_NAME" "$RESET"
    printf 'Project chats: %s | documents: %s\n' "$chats" "$docs"
    printf 'Project memory: %s | knowledge chunks: %s\n' "$pnotes" "$pchunks"
    printf 'Global memory: %s | knowledge chunks: %s\n' "$gnotes" "$gchunks"
    printf 'Librarian: %s | Neuron: %s\n' "$LIBRARIAN_MODEL" "$NEURON_MODEL"
    printf 'Semantic retrieval: %s\n\n' "$embed"
}

command_learn() {
    local mode="$1"
    printf '%bBrain learning · %s%b\n\n' "$WHITE" "$CURRENT_PROJECT_NAME" "$RESET"
    brain_learn_project "$mode"
    printf 'Learned: %s | Unchanged: %s | Failed: %s\n' "$BRAIN_LEARNED" "$BRAIN_SKIPPED" "$BRAIN_FAILED"
    [[ -z "$BRAIN_LAST_FAILURES" ]] || printf '\nFailures:\n%s\n' "$BRAIN_LAST_FAILURES"
    printf '\n'
}

command_prompt_inspect() {
    local file="$AKRO_RUNTIME_DIR/last-prompt.json"
    [[ -f "$file" ]] || { ui_notice 'No model prompt has been sent yet.' "$GRAY"; return 1; }
    printf '%bLast model request%b\n\n' "$WHITE" "$RESET"
    jq -r '"Model: "+.model+"\nProject: "+.project+"\nSkills: "+(.skills//"none")+"\nMessages: "+((.messages|length)|tostring)+"\nApprox chars: "+((.messages|map(.content|length)|add//0)|tostring)+"\n\n--- MESSAGES ---\n"+(.messages|to_entries|map("\n["+(.value.role|ascii_upcase)+"]\n"+.value.content)|join("\n"))' "$file"
    printf '\n'
}

command_clear_project() {
    local answer=""
    printf '%bCLEAR PROJECT%b\n\nThis deletes chats, documents, generated memory, and knowledge for %s.\nType CLEAR to confirm: ' "$RED" "$RESET" "$CURRENT_PROJECT_NAME"
    IFS= read -r answer || true
    if [[ "$answer" == CLEAR ]]; then
        rm -rf "$CURRENT_PROJECT_DIR/chats" "$CURRENT_PROJECT_DIR/documents" "$CURRENT_PROJECT_DIR/brain" "$CURRENT_PROJECT_DIR/knowledge"
        project_scope_init "$CURRENT_PROJECT_DIR"; chat_new; ui_notice 'Project data cleared.' "$GREEN"
    else ui_notice 'CLEAR cancelled.' "$GRAY"; fi
}

handle_user_command() {
    local input="$1"
    case "$input" in
        /quit|/exit|/bye) return 10 ;;
        /help|/?) command_help; return 0 ;;
        /model) command_model_picker; return 0 ;;
        /chats) command_chat_picker; return 0 ;;
        /new) chat_new; ui_redraw; return 0 ;;
        /skills) skill_list; printf '\n'; return 0 ;;
        /brain) command_brain_status; return 0 ;;
        /memory) command_memory_picker; return 0 ;;
        /learn) command_learn incremental; return 0 ;;
        /learn-all) command_learn all; return 0 ;;
        /prompt) command_prompt_inspect; return 0 ;;
        /project) command_project_picker; return 0 ;;
        /project\ *) chat_new; project_use "${input#/project }"; ui_redraw; ui_notice "Project: $CURRENT_PROJECT_NAME" "$GREEN"; return 0 ;;
        /save) ui_notice 'Usage: /save name' "$GRAY"; return 0 ;;
        /save\ *) command_save_chat "${input#/save }"; return 0 ;;
        /CLEAR) command_clear_project; return 0 ;;
    esac
    return 1
}
