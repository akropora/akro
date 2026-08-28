#!/bin/bash
set -e

INSTALL_DIR="$HOME/user/chat"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

[ "$(uname)" = "Darwin" ] || {
  echo "Akro currently supports macOS only."
  exit 1
}

for cmd in curl jq glow ollama; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Missing dependency: $cmd"
    exit 1
  }
done

curl -fsS 'http://127.0.0.1:11434/api/tags' >/dev/null 2>&1 || {
  echo "Start Ollama, then run install.sh again."
  exit 1
}

models=$(ollama list | awk 'NR > 1 {print $1}')
[ -n "$models" ] || {
  echo "Install at least one Ollama model first."
  exit 1
}

echo "Choose the default model:"
i=0
while IFS= read -r model; do
  i=$((i + 1))
  printf '  %d) %s\n' "$i" "$model"
done <<EOF_MODELS
$models
EOF_MODELS

while true; do
  printf '> '
  IFS= read -r choice
  model=$(printf '%s\n' "$models" | sed -n "${choice}p")
  [ -n "$model" ] && break
  echo "Invalid choice."
done

mkdir -p "$INSTALL_DIR/conversations" "$INSTALL_DIR/modelfiles" "$INSTALL_DIR/system-prompts"
cp "$SOURCE_DIR/chat.sh" "$INSTALL_DIR/chat.sh"
cp "$SOURCE_DIR/skills.json" "$INSTALL_DIR/skills.json"
cp "$SOURCE_DIR/modelfiles/neuron" "$INSTALL_DIR/modelfiles/neuron"
[ -f "$SOURCE_DIR/system-prompts/README.md" ] && cp "$SOURCE_DIR/system-prompts/README.md" "$INSTALL_DIR/system-prompts/README.md"
printf 'MODEL=%s\n' "$model" > "$INSTALL_DIR/.config"
chmod +x "$INSTALL_DIR/chat.sh"

if ! ollama show qwen3:0.6b >/dev/null 2>&1; then
  echo "Pulling qwen3:0.6b for Neuron..."
  ollama pull qwen3:0.6b
fi

echo "Creating Neuron..."
ollama create neuron -f "$INSTALL_DIR/modelfiles/neuron"

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/akro" <<EOF_AKRO
#!/bin/bash
AKRO_HOME="$INSTALL_DIR" exec "$INSTALL_DIR/chat.sh" "\$@"
EOF_AKRO
chmod +x "$HOME/.local/bin/akro"

if ! printf '%s' ":$PATH:" | grep -Fq ":$HOME/.local/bin:"; then
  line='export PATH="$HOME/.local/bin:$PATH"'
  grep -Fq "$line" "$HOME/.zshrc" 2>/dev/null || printf '\n# Akro\n%s\n' "$line" >> "$HOME/.zshrc"
fi

echo
echo "Akro installed in $INSTALL_DIR"
echo "Default model: $model"
echo "Run: akro"
