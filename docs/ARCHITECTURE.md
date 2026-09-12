# Architecture

Akro is a Bash + JSON terminal AI built around Ollama.

## Core runtime

- `chat.sh`: interactive loop
- `lib/ollama.sh`: Ollama chat and stream helpers
- `lib/skills.sh`: skill discovery and composition
- `lib/brain.sh`: second-brain retrieval and learning
- `lib/knowledge.sh`: document indexing and retrieval
- `lib/projects.sh`: project isolation
- `lib/ui.sh`: terminal rendering and activity

## v4 Agentic

Agentic uses three deliberately small layers:

1. Supervisor: the current selected model plans, reviews action results, and writes the final response.
2. Executor: `coral1.6-agent` converts one plain-English instruction into one escaped action line.
3. Runtime: Akro parses that line, enforces workspace and permission rules, executes it, logs it, and returns the exact action/result to the supervisor.

There is no tool registry, JSON executor schema, objective graph, dependency generation system, or semantic completion engine in v4.
