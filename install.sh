#!/bin/bash
set -e

AKRO_REPO="akropora/akro"
AKRO_BRANCH="main"
INSTALL_DIR="$HOME/user/chat"
RAW_URL="https://raw.githubusercontent.com/$AKRO_REPO/$AKRO_BRANCH"

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
  echo "Start Ollama, then run the installer again."
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
done <<EOF
$models
EOF

while true; do
  printf '> '
  IFS= read -r choice </dev/tty

  case "$choice" in
    ''|*[!0-9]*)
      echo "Enter a number from the list."
      continue
      ;;
  esac

  model=$(printf '%s\n' "$models" | sed -n "${choice}p")

  if [ -n "$model" ]; then
    break
  fi

  echo "Invalid choice."
done

mkdir -p "$INSTALL_DIR/conversations" "$INSTALL_DIR/modelfiles"

fetch() {
  curl -fsSL "$RAW_URL/$1" -o "$INSTALL_DIR/$1"
}

echo "Installing Akro..."

fetch chat.sh
fetch skills.json
fetch modelfiles/neuron

printf 'MODEL="%s"\n' "$model" > "$INSTALL_DIR/.config"
chmod +x "$INSTALL_DIR/chat.sh"

if ! ollama show qwen3:0.6b >/dev/null 2>&1; then
  echo "Pulling qwen3:0.6b for Neuron..."
  ollama pull qwen3:0.6b
fi

echo "Creating Neuron..."
ollama create neuron -f "$INSTALL_DIR/modelfiles/neuron"

mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/akro" <<EOF
#!/bin/bash
AKRO_HOME="$INSTALL_DIR" exec "$INSTALL_DIR/chat.sh" "\$@"
EOF

chmod +x "$HOME/.local/bin/akro"

if ! printf '%s' ":$PATH:" | grep -Fq ":$HOME/.local/bin:"; then
  line='export PATH="$HOME/.local/bin:$PATH"'

  grep -Fq "$line" "$HOME/.zshrc" 2>/dev/null ||
    printf '\n# Akro\n%s\n' "$line" >> "$HOME/.zshrc"
fi

echo
echo "Akro installed."
echo "Default model: $model"
echo
echo "Run:"
echo "  akro"

if ! printf '%s' ":$PATH:" | grep -Fq ":$HOME/.local/bin:"; then
  echo
  echo "Open a new Terminal window first, or run:"
  echo "  source ~/.zshrc"
fi