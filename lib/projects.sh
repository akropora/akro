#!/usr/bin/env bash

CURRENT_PROJECT_SLUG="${CURRENT_PROJECT_SLUG:-}"
CURRENT_PROJECT_NAME="${CURRENT_PROJECT_NAME:-}"
CURRENT_PROJECT_DIR="${CURRENT_PROJECT_DIR:-}"

project_init_root() {
    mkdir -p "$AKRO_DATA_DIR" "$AKRO_GLOBAL_DIR" "$AKRO_PROJECTS_DIR" "$AKRO_RUNTIME_DIR"
    akro_json_file_init "$AKRO_STATE_FILE" '{"version":2,"current_project":"default"}'
    local slug=""
    slug="$(jq -r '.current_project // "default"' "$AKRO_STATE_FILE" 2>/dev/null || printf 'default')"
    project_scope_init "$AKRO_GLOBAL_DIR"
    if [[ ! -d "$AKRO_PROJECTS_DIR/sandbox" ]]; then project_create sandbox >/dev/null; fi
    project_use "$slug" >/dev/null || project_use default >/dev/null
}

project_scope_init() {
    local root="$1"
    mkdir -p "$root/chats" "$root/documents" "$root/brain/notes" "$root/knowledge/chunks"
    akro_json_file_init "$root/brain/index.json" '{"version":2,"sources":{}}'
    akro_json_file_init "$root/brain/ignored.json" '{"version":2,"source_ids":[]}'
    akro_json_file_init "$root/knowledge/index.json" '{"version":2,"chunks":{}}'
}

project_create() {
    local name="$1" slug=""
    slug="$(akro_slug "$name")"
    [[ "$slug" != "global" ]] || { printf 'global is reserved for cross-project memory.\n' >&2; return 1; }
    project_scope_init "$AKRO_PROJECTS_DIR/$slug"
    local isolated=false
    [[ "$slug" == "sandbox" ]] && isolated=true
    akro_json_file_init "$AKRO_PROJECTS_DIR/$slug/project.json" "$(jq -n --arg name "$name" --arg slug "$slug" --arg created "$(akro_timestamp)" --argjson isolated "$isolated" '{version:2,name:$name,slug:$slug,created:$created,isolated:$isolated}')"
    printf '%s' "$slug"
}

project_use() {
    local requested="$1" slug="" name=""
    slug="$(akro_slug "$requested")"
    if [[ ! -d "$AKRO_PROJECTS_DIR/$slug" ]]; then
        project_create "$requested" >/dev/null || return 1
    fi
    project_scope_init "$AKRO_PROJECTS_DIR/$slug"
    name="$(jq -r '.name // empty' "$AKRO_PROJECTS_DIR/$slug/project.json" 2>/dev/null || true)"
    [[ -n "$name" ]] || name="$requested"
    CURRENT_PROJECT_SLUG="$slug"
    CURRENT_PROJECT_NAME="$name"
    CURRENT_PROJECT_DIR="$AKRO_PROJECTS_DIR/$slug"
    jq --arg slug "$slug" '.current_project=$slug' "$AKRO_STATE_FILE" | akro_atomic_write "$AKRO_STATE_FILE"
}

project_list() {
    local dir="" name="" slug=""
    for dir in "$AKRO_PROJECTS_DIR"/*; do
        [[ -d "$dir" ]] || continue
        slug="$(basename "$dir")"
        name="$(jq -r '.name // empty' "$dir/project.json" 2>/dev/null || true)"
        [[ -n "$name" ]] || name="$slug"
        printf '%s\t%s\n' "$slug" "$name"
    done | sort -t $'\t' -k2,2
}

project_is_isolated() { [[ "${CURRENT_PROJECT_SLUG:-}" == "sandbox" ]] || jq -e ' .isolated == true ' "$CURRENT_PROJECT_DIR/project.json" >/dev/null 2>&1; }
