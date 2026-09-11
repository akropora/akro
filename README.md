# Akro V2.2

Akro is a local-first terminal AI environment for Ollama. It combines normal chat, explicit slash-command skills, project-scoped memory, searchable plain-text knowledge, small helper models, and now a bounded tool-using agent.

V2.2 adds one major idea: **small local models can do real work when Akro gives them safe tools, compact context, and a tight execution loop.**

## Highlights

- Local Ollama chat with streaming output
- Glow-rendered finished responses
- Folder-based skills with automatic discovery
- Explicit, stackable slash-command skills
- `/promptup`, `/work`, `/critic`, `/verify`, `/decision`
- New `/agentic` file-and-code agent
- Project-specific chats, memory, documents, and knowledge
- Built-in isolated `sandbox`
- Background remembering with Librarian
- Hybrid retrieval with optional embeddings
- Plain-text document chunking and retrieval
- Official `AKRO_VISIBLE_MODELS` allowlist
- Braille activity loaders across slow operations
- `/prompt` inspection for debugging transformed prompts

## Requirements

Required:

- macOS or another Unix-like system with Bash
- [Ollama](https://ollama.com/)
- `curl`
- `jq`
- standard shell tools such as `awk`, `sed`, `grep`, `find`, `mktemp`, `tput`, and `stty`

Recommended:

- [Glow](https://github.com/charmbracelet/glow) for Markdown rendering
- `rg` / ripgrep for faster Agentic search
- `perl` for Agentic's exact `replace_text` tool
- `shellcheck` for optional shell verification
- Tavily API key for `/search`
- `embeddinggemma:latest` for semantic retrieval

## Install

```bash
git clone https://github.com/akropora/akro.git
cd akro
chmod +x chat.sh install.sh lib/remember-worker.sh skills/*/run.sh tests/*.sh
./install.sh
```

Then run:

```bash
akro
```

or directly:

```bash
./chat.sh
```

Persistent Akro data lives outside the repo in:

```text
~/.akro/
```

Your local `.env` also stays outside Git history because it is ignored by `.gitignore`.

## Helper models

Akro uses small helper models for specific jobs.

```bash
ollama pull akropora/neuron:latest
ollama pull akropora/librarian:latest
ollama pull akropora/coral1.6-prompt:latest

ollama cp akropora/neuron:latest neuron:latest
ollama cp akropora/librarian:latest librarian:latest
ollama cp akropora/coral1.6-prompt:latest coral1.6-prompt:latest
```

V2.2 also introduces `coral1.6-agent`. Until it is published under `akropora`, create it from the Modelfile provided with the V2.2 release instructions. After publication, users can install it with:

```bash
ollama pull akropora/coral1.6-agent:latest
ollama cp akropora/coral1.6-agent:latest coral1.6-agent:latest
```

## Configuration

Create a local environment file:

```bash
cp examples/.env.example .env
```

Important examples:

```bash
DEFAULT_MODEL="coral1.6:latest"
NEURON_MODEL="neuron:latest"
LIBRARIAN_MODEL="librarian:latest"
PROMPT_MODEL="coral1.6-prompt:latest"
AGENT_MODEL="coral1.6-agent:latest"
TAVILY_API_KEY=""
```

### Limit models shown by `/model`

```bash
AKRO_VISIBLE_MODELS="coral1.6:latest,coral1.6-worker:latest,coral1.6-coder:latest"
```

If `AKRO_VISIBLE_MODELS` is empty, Akro lists every installed Ollama model.

## Main commands

```text
/model             choose an installed Ollama model
/chats             browse chats in the current project
/new               start a new chat
/save name         rename the current chat
/project           switch projects
/project name      create or switch to a project
/sandbox           switch to fully isolated Sandbox
/memory            browse Brain notes
/learn             learn changed project sources
/learn-all         rebuild project Brain notes
/brain             show memory and knowledge status
/skills            show detected skills
/prompt            inspect the last main-model prompt
/CLEAR             clear the current project
/help              show help
/quit              exit
```

## Skills

Skills are explicit suffix commands and can be stacked.

```text
Explain this simply /concise
Fix this code /plsfix
Search current information /search
Turn this rough request into a stronger prompt /promptup
Solve this complex task deeply /work
Find weaknesses in this plan /critic
Check this result carefully /verify
Make a hard choice /decision
Inspect and fix this repository /agentic
```

### Promptup + Agentic

One of V2.2's strongest combinations is:

```text
clean up this repo and fix the rendering bug /promptup /agentic
```

`/promptup` first turns the rough request into clearer instructions. `/agentic` then uses those instructions to inspect the workspace, make approved changes, run checks, observe the results, and finish with a summary.

`/agentic` completes the turn itself, so it must be the last skill in a pipeline.

## Agentic

`/agentic` is different from `/work`.

```text
/work
think deeply -> produce a finished model response

/agentic
inspect -> act -> observe -> revise -> verify -> finish
```

By default, Agentic uses the directory where Akro was launched as its workspace:

```bash
cd ~/projects/my-repo
akro
```

Then:

```text
Find the Markdown rendering bug, fix it, and verify the shell syntax /agentic
```

You can restrict it to a child directory:

```text
Clean up the tests /agentic [tests]
```

### Agent tools

V2.2 intentionally does **not** give a 2B model unrestricted shell access. It gets a curated toolbox:

- `list_files`
- `read_file`
- `search_files`
- `write_file`
- `replace_text`
- `make_directory`
- `run_check`

`run_check` supports controlled checks including Git status/diff, Bash syntax, JSON validation, optional ShellCheck, and test scripts under `tests/`.

### Permissions

Reads happen automatically. Writes require confirmation by default:

```text
Agent wants to replace text in: lib/ui.sh
Allow? [y/N]
```

Set this in `.env` only if you deliberately want full write permission inside the workspace:

```bash
AGENT_CONFIRM_WRITES=0
```

Akro blocks Agentic from directly reading or modifying `.git`, `.env`, `.ssh`, paths outside the workspace, and symlink targets.

### Agent limits

Useful `.env` settings:

```bash
AGENT_MODEL="coral1.6-agent:latest"
AGENT_MAX_STEPS=20
AGENT_NUM_CTX=8192
AGENT_NUM_PREDICT=1600
AGENT_MAX_READ_CHARS=18000
AGENT_MAX_TOOL_OUTPUT=12000
AGENT_MAX_WRITE_CHARS=50000
AGENT_CONTEXT_MAX_CHARS=2200
AGENT_CONFIRM_WRITES=1
AGENT_REPEAT_LIMIT=2
```

These defaults are intentionally reasonable for an 8 GB Apple Silicon machine. A 16 GB machine can raise `AGENT_NUM_CTX` if needed.

Every agent run writes a lightweight JSONL execution log under the active project's data directory:

```text
~/.akro/projects/<project>/agent/runs/
```

## Projects and Sandbox

Projects keep unrelated work separate. Each project has its own chats, memory, documents, and knowledge.

```text
/project
/project akro
```

Akro automatically creates `sandbox`:

```text
/sandbox
```

Sandbox is fully isolated. Chats still save locally, but no global/project memory is retrieved, nothing is written to long-term Brain memory, and documents are not permanently indexed.

## Background remembering

After a normal response, Akro queues only the newest user/assistant turn for Librarian in the background. You immediately get the prompt back while remembering finishes independently.

```text
[/ remembering in background...]
```

This keeps small-model chat responsive without giving up long-term memory.

## Plain-text documents

Akro intentionally focuses on readable text files. Use:

```text
Summarize this /document [~/notes/report.txt]
```

Ordinary projects copy, chunk, index, and learn documents. Sandbox only supplies small documents to the current request and never persists them.

## Repository layout

```text
akro/
  chat.sh
  config.sh
  install.sh

  lib/
    common.sh
    ui.sh
    ollama.sh
    projects.sh
    chats.sh
    brain.sh
    knowledge.sh
    skills.sh
    commands.sh
    remember-worker.sh

  skills/
    concise/
    plsfix/
    caveman/
    search/
    document/
    promptup/
    work/
    critic/
    verify/
    decision/
    agentic/

  docs/
  examples/
  tests/
```

## Test

```bash
./tests/smoke.sh
```

For the whole shell tree:

```bash
find . -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

## Design philosophy

Akro stays intentionally small:

- local first
- small models first
- retrieval over giant prompts
- explicit tools over hidden automation
- skills install without editing Akro core
- tiny helper models handle narrow infrastructure jobs
- slow work stays visibly alive
- Bash and JSON unless complexity genuinely earns something heavier

V2.2 extends that philosophy to agents: **give small models useful hands, but keep Akro in control of what those hands can touch.**
