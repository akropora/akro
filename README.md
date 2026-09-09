# Akro V2

Akro is a local-first terminal AI environment built around Ollama, Bash, JSON, small helper models, explicit slash-command skills, long-term memory, and project-scoped knowledge.

V2 keeps the parts that made V1 simple, but changes the architecture so Akro can grow without turning into one giant shell script.

## What changed in V2

- Folder-based skills with automatic discovery
- Slash commands remain the only way skills are invoked
- Skills can be added without editing Akro core files
- Project-specific chats, documents, memory, and knowledge
- Global memory that can follow you across projects
- Hybrid Brain retrieval using keywords, importance, recency, and optional embeddings
- Separate long-term memory and exact document knowledge
- Plain-text document chunking and immediate indexing
- Automatic Brain learning after chat turns
- `/memory` browser with inspect, edit, delete, and global promotion
- `/project` project switching
- `/prompt` inspection for debugging model context
- Streaming Ollama responses
- Visible activity indicators for slow work
- Centralized configuration
- Smaller, modular core files

## Design philosophy

Akro V2 is built around a few rules:

1. Local first.
2. Small models first.
3. Small context windows first.
4. Retrieval is better than giant prompts.
5. Skills should be explicit slash commands.
6. Installing a skill should not require editing Akro core.
7. Tiny helper models should organize information so the main model can focus on the answer.
8. Memory should stay understandable.
9. Slow work should always look alive.
10. Stay Bash and JSON unless there is a strong reason not to.

## Requirements

Required:

- Bash
- Ollama
- `curl`
- `jq`
- standard Unix tools such as `awk`, `sed`, `grep`, `cksum`, `mktemp`, `tput`, and `stty`

Optional:

- `glow` for pretty Markdown rendering when reopening chat history
- Tavily API key for `/search`
- `embeddinggemma:latest` for semantic retrieval

Akro still works without an embedding model. It falls back to keyword, importance, and recency scoring.

## Quick start

```bash
git clone <your-akro-repo-url>
cd akro
chmod +x chat.sh install.sh
./install.sh
./chat.sh
```

Or run it directly without installing a launcher:

```bash
./chat.sh
```

Akro stores user data in:

```text
~/.akro/
```

The repository itself stays clean.

## Recommended Ollama models

Akro can chat with any installed Ollama model.

The default helper model names are:

```text
neuron:latest       titles and lightweight organization
librarian:latest    long-term memory extraction
embeddinggemma:latest   semantic retrieval, optional
```

Change any of these in `.env` or with environment variables.

## Configuration

Copy the example environment file:

```bash
cp examples/.env.example .env
```

Then edit what you need.

Environment variables override `config.sh` defaults.

## Main commands

```text
/model             choose an Ollama model
/chats             browse chats in the current project
/new               start a new chat
/save name         rename the current chat
/project           switch projects
/project name      create or switch to a project
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

Skills are explicit suffix commands.

```text
Explain this simply /concise
Fix this function /plsfix
What changed in Ollama this week? /search
Summarize this /document [~/notes/report.txt]
```

Skills can stack:

```text
Fix this function and keep the answer short /plsfix /concise
```

Each skill lives in its own folder:

```text
skills/
  concise/
    skill.json
  search/
    skill.json
    run.sh
```

Akro discovers valid skill folders automatically.

See `docs/SKILLS.md` for the skill format.

## Projects

Projects isolate unrelated work.

```bash
/project akro
/project school
/project personalysis
```

Each project gets its own:

```text
chats/
documents/
brain/
knowledge/
```

Global Brain memory lives separately and is available to every project.

Inside `/memory`, a project note can be promoted to global memory with `G`.

## Brain V2

Akro separates two ideas that V1 mixed together.

### Memory

Compact generated notes about useful context, preferences, decisions, goals, projects, and facts.

### Knowledge

Exact chunks from imported plain-text documents.

When Akro builds a prompt, it retrieves a small amount of relevant information from both systems. This is designed to make small local models useful without feeding them huge context windows.

## Plain-text documents

V2 intentionally stays simple and fast.

`/document` accepts readable plain-text files only. That includes things like:

```text
.txt
.md
.json
.csv
source code
configuration files
```

A document is copied into the active project, chunked, indexed, summarized by Librarian, and made searchable immediately.

Small documents can also be included directly in the current request. Large documents rely on retrieval instead of flooding the main model context.

## Streaming and activity

Main model responses stream as they arrive from Ollama.

Longer operations show activity states such as:

```text
[thinking...]
[searching...]
[indexing document...]
[remembering...]
```

The goal is simple: Akro should never look frozen while it is working.

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

  skills/
    concise/
    plsfix/
    caveman/
    search/
    document/

  docs/
    ARCHITECTURE.md
    SKILLS.md
    MIGRATION.md

  examples/
    .env.example

  tests/
    smoke.sh
```

## Test the repository

```bash
./tests/smoke.sh
```

The smoke test checks shell syntax, skill manifests, required files, and executable tool skills without requiring Ollama to be running.

## V2 scope decisions

V2 intentionally does not include:

- automatic skill selection
- PDF parsing
- Word document parsing
- OCR
- spreadsheet parsing
- model-specific writing or coding profiles

Those can come later if they earn their complexity.
