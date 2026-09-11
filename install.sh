#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/akro"

mkdir -p "$BIN_DIR"

# Important: remove an old file or symlink first.
# Writing through an existing symlink could overwrite chat.sh.
rm -f "$BIN"

cat > "$BIN" <<EOF
#!/usr/bin/env bash
AKRO_ROOT="$ROOT" exec "$ROOT/chat.sh" "\$@"
EOF

chmod +x "$BIN"

printf 'Installed Akro launcher:\n  %s\n' "$BIN"
printf 'Akro root:\n  %s\n' "$ROOT"
