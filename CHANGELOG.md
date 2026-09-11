# Changelog

## 2.2.0

- Added `/agentic`, a bounded multi-step file and code agent.
- Added a completed-tool skill protocol so agent skills can finish a chat turn directly.
- Added current-directory workspace capture and optional child-workspace targeting.
- Added curated Agentic tools for listing, reading, searching, writing, replacing, creating directories, and controlled checks.
- Added write confirmation, path traversal protection, `.git`/`.env`/`.ssh` protection, symlink rejection, output caps, step limits, and loop detection.
- Added lightweight JSONL agent run logs.
- Added `AGENT_MODEL` and Agentic runtime configuration.
- Standardized activity animation on the Braille spinner sequence.
- Replaced the macOS-incompatible fractional `read -t` streaming loop with a separate 0.10-second spinner process.
- Explicitly disabled Ollama think output in the main streaming path to prevent empty-content responses with reasoning models.
- Preserved V2.1 projects, Sandbox isolation, Promptup, background remembering, knowledge retrieval, and visible-model filtering.
