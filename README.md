# Akro v4

Akro is a local-first terminal AI for Ollama. v4 keeps the skill surface small and rebuilds `/agentic` around a tiny text action protocol instead of JSON tool calling.

## Skills

Akro v4 ships with exactly four skills:

- `/document [path]` - attach and index a local plain-text document
- `/search` - search the live web with Tavily
- `/concise` - make the final answer shorter and more direct
- `/agentic [workspace]` - let the current model supervise on-machine actions

## Agentic v4

The selected Akro model is the supervisor. `coral1.6-agent` is only an action compiler.

```text
user task
  -> current model makes a short plan and gives one next instruction
  -> coral1.6-agent returns one escaped action line
  -> Akro parses, validates, asks permission when needed, and executes
  -> current model reviews the exact action and result
  -> repeat until complete
```

The executor never plans and never writes the final answer.

### Action protocol

```text
READ|path
WRITE|path|content
APPEND|path|content
REPLACE|path|old|new
DELETE|path
EXISTS|path
LIST|path
SEARCH|path|query
SHELL|command
WEB|query
```

Escapes are `\\`, `\|`, `\n`, `\t`, and `\r`. The executor must return exactly one physical line. Invalid output gets one direct repair attempt.

v4 intentionally removes the v3 tool registry, executor JSON schemas, objective graph, dependency generations, and runtime completion engine.

## Permissions

Normal workspace reads and writes run automatically. Akro asks before:

- deleting a file
- web search
- sensitive paths such as `.env`, `.ssh`, `.aws`, and `.git`
- shell commands outside a tiny read-only allowlist

Paths that escape the workspace are blocked in the first v4 implementation.

## Requirements

- macOS or Linux
- Bash 3.2+
- Ollama
- `curl`
- `jq`
- Python 3 for exact `REPLACE`
- optional `rg`, `glow`, `shellcheck`
- Tavily API key for `/search` and Agentic `WEB`

## Install

```bash
chmod +x chat.sh install.sh lib/remember-worker.sh skills/*/run.sh tests/*.sh
./tests/smoke.sh
./install.sh
```

The directory where you launch `akro` becomes the Agentic workspace.

## Executor model

Pull MiniCPM5-2B:

```bash
ollama pull openbmb/minicpm5-2b:latest
```

Build the v4 executor Modelfile supplied with the release:

```bash
ollama create coral1.6-agent -f Modelfile.coral1.6-agent-v4
```

Then set:

```bash
AGENT_MODEL="coral1.6-agent:latest"
```

## Recommended Agentic settings

```bash
AGENT_MODEL="coral1.6-agent:latest"
AGENT_MAX_STEPS=12
AGENT_NUM_CTX=4096
AGENT_NUM_PREDICT=300
AGENT_CONTROLLER_NUM_CTX=8192
AGENT_CONTROLLER_NUM_PREDICT=900
AGENT_MAX_READ_CHARS=20000
AGENT_MAX_TOOL_OUTPUT=16000
AGENT_MAX_WRITE_CHARS=80000
AGENT_ACTION_MAX_CHARS=100000
AGENT_SHOW_TOOLS=1
AGENT_SHOW_PLAN=1
AGENT_SHOW_INSTRUCTIONS=1
AGENT_VERBOSE=1
AGENT_COMMAND_TIMEOUT=120
```

## First tests

```text
Create agent-test.txt in the workspace root containing exactly "hello from akro" followed by a newline, then read it back and verify the contents. /agentic
```

```text
Create agent-delete-test.txt containing "delete me", delete it, and verify it no longer exists. /agentic
```

```text
Find the file in this workspace containing command_model_picker and tell me its path. Do not edit anything. /agentic
```

```text
Check the Git status of this repository and summarize uncommitted changes. Do not modify anything. /agentic
```
