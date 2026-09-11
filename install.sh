#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
chmod +x "$ROOT/chat.sh" "$ROOT/lib/remember-worker.sh" "$ROOT"/skills/*/run.sh "$ROOT"/tests/*.sh 2>/dev/null || true
cat > "$BIN_DIR/akro" <<EOF
#!/usr/bin/env bash
AKRO_ROOT="$ROOT" exec "$ROOT/chat.sh" "\$@"
EOF
chmod +x "$BIN_DIR/akro"
printf 'Akro launcher installed: %s/akro\n' "$BIN_DIR"
printf 'The directory you launch Akro from becomes the default /agentic workspace.\n'
printf 'Add %s to PATH if it is not already there.\n' "$BIN_DIR"
printf 'Run: akro\n'
