# Changelog

## 2.0.0

- Added folder-based, auto-discovered skills.
- Kept explicit slash commands as the skill interface.
- Added project-scoped chats, memory, documents, and knowledge.
- Added global Brain memory and project-to-global memory promotion.
- Split generated long-term memory from exact document knowledge.
- Added plain-text document chunking and immediate indexing.
- Added hybrid retrieval using keyword overlap, importance, recency, and optional Ollama embeddings.
- Added hard retrieval context budgets for small-model use.
- Added automatic Brain refresh after chat turns.
- Added `/memory`, `/project`, `/prompt`, and expanded `/brain` tooling.
- Added streamed Ollama responses and activity indicators.
- Added centralized configuration and modular shell libraries.
- Added smoke tests and migration/skill/architecture documentation.
