#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
chmod +x "$ROOT/chat.sh" "$ROOT/lib/remember-worker.sh" "$ROOT"/skills/*/run.sh "$ROOT"/tests/*.sh 2>/dev/null || true
ln -sf "$ROOT/chat.sh" "$BIN_DIR/akro"
printf 'Akro launcher installed: %s/akro\n' "$BIN_DIR"
printf 'Add %s to PATH if it is not already there.\n' "$BIN_DIR"
printf 'Run: akro\n'
