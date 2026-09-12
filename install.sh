#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${HOME}/.local/bin"
BIN="$BIN_DIR/akro"
mkdir -p "$BIN_DIR"
chmod +x "$ROOT/chat.sh" "$ROOT/lib/remember-worker.sh" "$ROOT"/skills/*/run.sh "$ROOT"/tests/*.sh 2>/dev/null || true
# Remove an old launcher or symlink before writing. This avoids following a
# legacy symlink back into chat.sh and overwriting the application.
rm -f "$BIN"
cat > "$BIN" <<LAUNCHER
#!/usr/bin/env bash
AKRO_ROOT="$ROOT" exec "$ROOT/chat.sh" "\$@"
LAUNCHER
chmod +x "$BIN"
printf 'Akro launcher installed: %s\n' "$BIN"
printf 'The directory you launch Akro from becomes the default /agentic workspace.\n'
printf 'Add %s to PATH if it is not already there.\n' "$BIN_DIR"
printf 'Run: akro\n'
