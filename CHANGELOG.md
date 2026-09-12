# Changelog

## 3.0.3

- Preserve trailing newlines and other exact text payloads when decoding JSON arguments for `write_file`, `append_file`, `replace_text`, and `apply_patch`.
- Fix `content_match` verification loops caused by hashing the requested text while Bash silently stripped trailing newlines before writing.
- Add a regression self-test that writes `ok\n`, verifies the byte count, and confirms read-back clears pending verification.

## 3.0.2

- Convert rejected supervisor completion into a mandatory executor step instead of another supervisor-only cycle.
- Force the first plan objective when no tool evidence exists.
- Force pending file verification immediately after a mutation until runtime proof is available.

## 3.0.1

- Reject supervisor `done` responses when the current Agentic run has no successful tool evidence.
- Treat conversation history and model assertions as non-authoritative for machine state.
- Track pending verification after file mutations.
- Require `read_file` verification after file writes and exact content-hash agreement for `write_file`.
- Require confirmed absence after deletes before completion.
- Normalize workspace-relative and absolute in-workspace paths for verification state.
- Log rejected completion attempts as `completion_rejected`.

## 3.0.0

- Rebuilt `/agentic` around a supervisor + executor + deterministic runtime architecture.
- Added a per-run structured state engine with dependency generations for workspace, Git, system, Ollama, and network domains.
- Added objective satisfaction, evidence reuse, volatile refresh rules, and successful tool-call caching.
- Added deduplicated mutation events so one action increments each affected domain at most once.
- Added a declarative `skills/agentic/tools.json` registry used for validation, tool cards, effects, and examples.
- Narrowed MiniCPM tool choices by objective kind.
- Replaced verbose schema-style executor prompting with small tool cards and valid examples.
- Added one direct executor repair attempt before supervisor intervention.
- Added dedicated Git, system, process, and Ollama inspection tools.
- Added hard no-progress limits and stronger repeat protection.
- Reworked Agentic logging so arbitrary model text cannot break JSONL logs.
- Preserved risk-based confirmation for sensitive, destructive, external, and web actions.
- Kept the official skill set at `/document`, `/search`, `/concise`, and `/agentic`.
- Retained the safe launcher installation fix that removes old launcher symlinks before writing the wrapper.

## 4.0.1

- Fixed v4 skill launch failure caused by stale v3 Agentic environment exports in `lib/skills.sh`.
- Removed obsolete `AGENT_EXECUTOR_RETRIES`, repeat/no-progress, and old confirmation variables from the skill launcher.
- Added `AGENT_ACTION_MAX_CHARS` to the environment passed to tool skills.

## 4.0.0

- Rebuilt Agentic around a tiny escaped one-line action protocol.
- Removed the v3 tool registry, JSON executor schema, objective state engine, dependency generations, and runtime completion graph.
- The selected model now supervises every action directly; Coral Agent only translates one instruction into one action line.
- Added strict one-line parsing, one executor repair attempt, minimal permission gates, and simple repeat protection.
