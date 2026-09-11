# Akro V2.1

Akro is a local-first terminal AI environment built around Ollama, Bash, explicit slash-command skills, small helper models, long-term memory, and project-scoped knowledge.

V2.1 focuses on making small models more capable without making Akro feel heavier: **retrieve the right context, refine the prompt, execute with the current model, and move slow memory work into the background.**

## Highlights

- Folder-based skills with automatic discovery
- Explicit, stackable slash commands
- `/promptup` prompt refinement using `coral1.6-prompt`
- `/work`, `/critic`, `/verify`, and `/decision`
- Project-specific chats, memory, documents, and knowledge
- Built-in fully isolated `sandbox` project
- Hybrid memory retrieval with optional embeddings
- Exact plain-text document retrieval
- Background incremental remembering
- Streaming responses plus ASCII activity loaders
- Automatic Glow repaint after streaming completes
- Official `AKRO_VISIBLE_MODELS` support
- `/prompt` inspection for debugging transformed prompts

## Requirements

Required:

- macOS or another Unix-like system with Bash
- Ollama
- `curl`
- `jq`
- standard tools such as `awk`, `sed`, `grep`, `cksum`, `mktemp`, `tput`, and `stty`

Optional:

- `glow` for rendered Markdown
- Tavily API key for `/search`

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

Akro stores persistent user data in:

```text
~/.akro/
```

## Install Akro helper models

Pull the latest Brain models:

```bash
ollama pull akropora/neuron:latest
ollama pull akropora/librarian:latest
ollama cp akropora/neuron:latest neuron:latest
ollama cp akropora/librarian:latest librarian:latest
```

Build Coral 1.6 Prompt from the included Modelfile:

```bash
ollama create coral1.6-prompt -f models/Modelfile.coral1.6-prompt
```

After `akropora/coral1.6-prompt` is published, users can pull and alias it the same way as Neuron and Librarian.

## Configuration

Create your local environment file:

```bash
cp examples/.env.example .env
```

Your `.env` is local and should not be committed.

### Show only selected chat models

Set a comma-separated allowlist:

```bash
AKRO_VISIBLE_MODELS="coral1.6:latest,coral1.6-worker:latest,coral1.6-coder:latest,qwen3.5:9b-q4_k_m"
```

If `AKRO_VISIBLE_MODELS` is blank or unset, `/model` lists every installed Ollama model.

## Commands

```text
/model             choose an Ollama model
/chats             browse chats in the current project
/new               start a new chat
/save name         rename the current chat
/project           switch projects
/project name      create or switch to a project
/sandbox           enter the isolated sandbox project
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

Skills are suffix slash commands and can be stacked.

```text
Explain this simply /concise
Fix this function /plsfix
What changed in Ollama this week? /search
Review this proposal /critic
Check this command before I run it /verify
Should I rewrite this service in Python? /decision
Solve this difficult task completely /work
Turn this rough idea into a better prompt /promptup
```

### Prompt refinement

`/promptup` sends the request plus a very small amount of relevant Brain context to `coral1.6-prompt`. The helper model rewrites the request into clearer instructions, then the currently selected model answers the improved prompt.

Akro visibly reports that the prompt was enhanced. `/prompt` lets you inspect what ultimately reached the main model.

### Powerful combinations

Small models often benefit from combining focused skills:

```text
rough request /promptup /work
```

Refine the instructions first, then apply the deep execution framework.

```text
architecture idea /work /critic
```

Build the solution, while instructing the main model to actively look for weaknesses.

```text
implementation request /promptup /work /verify
```

Clarify the task, execute it deeply, then verify the result before finalizing.

```text
current technical question /search /promptup /work /verify
```

Research, refine, execute, and check in one explicit pipeline.

Akro shows the active skill pipeline so tool use never feels hidden.

## Background remembering

V2.1 no longer makes you wait for Librarian after every response.

After the main model finishes, Akro snapshots only the newest user/assistant turn and queues a compact Librarian job in the background. The next prompt becomes available immediately.

```text
[/ remembering in background...]
```

On a later prompt cycle, Akro reports when the background job completed.

Incremental remembering uses a much smaller context and output budget than full `/learn`, which reduces latency and memory pressure. Full project rebuilds remain available through `/learn-all`.

## Sandbox

Akro creates a `sandbox` project automatically.

Enter it with:

```text
/sandbox
```

Sandbox is fully isolated:

- chats still save locally
- no global or project memory is retrieved
- chats are never written into long-term memory
- documents are not copied, indexed, or remembered
- small `/document` files can be supplied temporarily to the current request
- nothing from Sandbox affects other projects

The header marks Sandbox as `[isolated]` so it is always obvious when memory is off.

## Brain and knowledge

Akro separates compact long-term **memory** from exact document **knowledge**.

For ordinary projects, Akro retrieves only a small amount of relevant information using keyword relevance, importance, recency, and optional semantic similarity. This is designed to help small models without requiring giant context windows.

## Activity and rendering

Slow operations use a shared ASCII activity loader, including thinking, search, prompt refinement, retrieval, indexing, and other tool work.

Main model output still streams immediately. When generation finishes, Akro repaints the conversation through Glow so Markdown is rendered without requiring `/skills` or another manual redraw.

## Plain-text documents

`/document [path]` intentionally supports readable plain-text files only. Ordinary projects copy, chunk, index, and learn the document immediately. Sandbox supplies small documents only for the current request and never persists them.

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

  models/
    Modelfile.coral1.6-prompt

  docs/
    ARCHITECTURE.md
    SKILLS.md
    MIGRATION.md
    UPGRADE.md

  examples/
    .env.example

  tests/
    smoke.sh
```

## Test

```bash
./tests/smoke.sh
```

You can also check all shell syntax with:

```bash
bash -n chat.sh config.sh lib/*.sh skills/*/run.sh
```

## Design principles

1. Local first.
2. Small models first.
3. Small context windows first.
4. Retrieval beats giant prompts.
5. Better prompts can unlock smaller models.
6. Tools stay explicit and visible.
7. Skills install without changing Akro core.
8. Tiny models organize while the selected model does the main work.
9. Memory should never block the next turn when it does not need to.
10. Every slow action should visibly feel alive.
11. Bash and JSON stay preferred until complexity genuinely earns something heavier.
