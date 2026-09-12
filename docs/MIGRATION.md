# Migration notes

Akro v4 keeps runtime state under `~/.akro/` and local configuration in `~/akro/.env`.

The major v4 change is Agentic. v3's structured tool registry and state engine are removed. v4 uses a one-line escaped action protocol. Existing Agentic JSONL logs remain readable as logs but are not runtime state.
