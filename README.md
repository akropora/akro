# Akro

Akro is a lightweight local AI environment built around Ollama.

It combines local chat, long-term memory, projects, searchable knowledge, and a modular skill system without requiring a large framework or cloud-hosted model.

The goal is simple:

> Make small local models more useful by giving them better memory, better retrieval, and better tools.

Akro is designed to stay fast, understandable, hackable, and local.

## Features

* Local chat powered by Ollama
* Switch between installed Ollama models
* Persistent conversation history
* Long-term memory
* Project-specific memory and knowledge
* Searchable document knowledge
* Hybrid retrieval for small context windows
* Optional semantic retrieval with embeddings
* Modular folder-based skills
* Automatic skill discovery
* Stackable slash-command skills
* Web search with Tavily
* Plain-text document ingestion
* Streaming model responses
* Live terminal activity indicators
* Prompt inspection and debugging
* Markdown rendering with Glow
* Automatic chat naming
* Memory browsing and management

## Requirements

Akro is currently designed for macOS and Bash.

You will need:

* macOS
* Bash
* Ollama
* `curl`
* `jq`
* `awk`
* `sed`

Optional:

* `glow` for Markdown rendering
* Tavily API key for `/search`
* an Ollama embedding model for semantic retrieval

## Install Ollama

Install Ollama from:

https://ollama.com

Then download at least one chat model.

For example:

```bash
ollama pull qwen3.5:4b
```

You can use any installed Ollama chat model with Akro.

To see your installed models:

```bash
ollama list
```

## Install Akro

Clone the repository:

```bash
git clone https://github.com/akropora/akro.git
cd akro
```

Make the scripts executable:

```bash
chmod +x chat.sh install.sh tests/*.sh
```

Run the installer:

```bash
./install.sh
```

Or start Akro directly:

```bash
./chat.sh
```

## Starting Akro

From the Akro directory:

```bash
./chat.sh
```

Akro will detect your installed Ollama models and open the terminal interface.

You can type normally to chat.

Example:

```text
you > Explain how DNS works.
```

## Main Commands

### Models

Choose an installed Ollama model:

```text
/model
```

Akro remembers the model used by each saved conversation.

### Conversations

Browse saved chats:

```text
/chats
```

Start a new conversation:

```text
/new
```

Rename the current conversation:

```text
/save My Chat Name
```

### Projects

Switch projects:

```text
/project
```

Projects keep related chats, memory, documents, and knowledge together.

For example, you might have:

```text
akro
school
work
personal
```

Project-specific information stays isolated from unrelated projects.

Akro can also maintain global memory that is available across projects.

### Memory

Browse stored memories:

```text
/memory
```

Akro's Brain is designed to preserve useful long-term information without placing your entire history into every prompt.

Memory retrieval considers relevance, importance, recency, and optionally semantic similarity.

### Brain Status

View Brain information:

```text
/brain
```

### Learn

Learn new or changed Brain sources:

```text
/learn
```

Rebuild generated Brain knowledge:

```text
/learn-all
```

Most newly imported documents are indexed immediately, so `/learn` is mainly useful for rebuilding or updating existing Brain sources.

### Prompt Inspection

Inspect what Akro is preparing for the model:

```text
/prompt
```

This is useful for debugging retrieval, skills, projects, and context usage.

### Help

```text
/help
```

or:

```text
/?
```

### Exit

```text
/quit
```

You can also use:

```text
/exit
/bye
```

## Multiline Input

Enter:

```text
"""
```

by itself to begin multiline mode.

Finish with another:

```text
"""
```

on its own line.

Example:

```text
you > """
... > Here is some code.
... > Please review it carefully.
... > """
```

## Skills

Akro uses slash-command skills.

Skills live in individual folders and are detected automatically.

Example structure:

```text
skills/
  concise/
    skill.json

  plsfix/
    skill.json

  search/
    skill.json
    run.sh
```

You do not need to edit Akro's main source code to install a new skill.

Drop a valid skill into the `skills/` directory and Akro can discover it.

View installed skills:

```text
/skills
```

## Using Skills

Prompt skills can modify how the model handles a request.

Example:

```text
Explain Docker networking /concise
```

Or:

```text
Fix this Bash function /plsfix
```

Skills can also be stacked:

```text
Fix this function /plsfix /concise
```

Akro intentionally uses explicit slash commands instead of automatically deciding which skills to run.

This keeps tool use predictable and under your control.

## Web Search

Akro includes a Tavily-powered search skill.

Example:

```text
What changed in the latest version of Ollama? /search
```

To use it, set your Tavily API key.

You can place it in your environment or Akro `.env` file:

```bash
TAVILY_API_KEY="your-key-here"
```

Never commit your real API key to GitHub.

## Documents

Akro V2 intentionally focuses on readable text files.

Example:

```text
Summarize this /document [~/Documents/notes.txt]
```

Akro can:

* copy the document into its local knowledge store
* split larger files into chunks
* index those chunks
* generate compact knowledge notes
* retrieve relevant sections later

This lets the model answer questions about documents without placing the entire document into every future prompt.

### Supported Documents

Akro currently focuses on readable text content, including files such as:

```text
.txt
.md
.json
.sh
.py
.js
html
source code
other plain-text formats
```

PDF, Word, spreadsheet, and OCR support are intentionally not part of V2 yet.

## Brain

Akro's long-term memory system is called Brain.

Brain has two main jobs.

### Memory

Memory stores useful long-term information such as:

* preferences
* goals
* project context
* decisions
* recurring facts
* important user context

Akro tries to avoid storing every trivial interaction as permanent memory.

### Knowledge

Knowledge stores searchable information from source documents and project material.

This distinction allows Akro to remember that something matters while still retrieving the exact source material when needed.

## Retrieval

Akro is designed around small context windows.

Instead of sending huge amounts of history to the model, Akro retrieves a small amount of relevant information.

Retrieval can consider:

* keywords
* importance
* recency
* semantic similarity

The result is a smaller, more focused prompt.

This is especially useful with smaller local models.

## Semantic Retrieval

Akro can optionally use Ollama embeddings.

If an embedding model is installed, Akro can use semantic similarity in addition to keyword matching.

For example:

```bash
ollama pull embeddinggemma
```

Akro will continue working without an embedding model.

Without embeddings, retrieval falls back to lexical relevance, importance, and recency.

## Projects

Projects provide isolated workspaces.

A project can contain its own:

```text
chats
documents
memory
knowledge
instructions
```

Akro may also maintain global memory that can be retrieved across projects.

Conceptually, the model receives only what is useful:

```text
relevant global memory
+
relevant project memory
+
relevant project knowledge
+
recent conversation
+
current request
```

This helps prevent unrelated information from filling the model's context window.

## Background Models

Akro can use small specialized Ollama models for background tasks.

Examples include:

* chat naming
* memory extraction
* document summaries
* retrieval support
* classification

The main chat model remains user-selectable.

A useful way to think about the architecture is:

> The chat model thinks. Small models organize.

## Streaming and Activity

Akro is designed so long operations do not appear frozen.

The terminal can display activity for tasks such as:

```text
thinking
searching
indexing
learning
retrieving memory
loading models
```

Model responses are streamed when supported by the current runtime.

## Configuration

Akro keeps major settings in a central configuration layer.

Settings can include:

* Akro directories
* Ollama API address
* default chat model
* Librarian model
* Brain model
* embedding model
* context size
* response limits
* retrieval limits
* project paths
* skill paths
* Tavily configuration
* UI behavior

Environment variables can override defaults.

## Environment File

Akro can load:

```text
.env
```

from the Akro directory.

Example:

```bash
TAVILY_API_KEY="..."
DEFAULT_MODEL="qwen3.5:4b"
```

Do not commit `.env` to GitHub.

## Repository Structure

The exact structure may evolve, but V2 follows this general layout:

```text
akro/
  chat.sh
  install.sh
  config.sh

  lib/
    ui.sh
    ollama.sh
    chats.sh
    commands.sh
    brain.sh
    memory.sh
    knowledge.sh
    projects.sh
    skills.sh

  skills/
    concise/
    plsfix/
    search/
    document/

  brain/

  projects/

  docs/
    ARCHITECTURE.md
    SKILLS.md
    MIGRATION.md

  tests/
```

## Creating Skills

Skills are meant to be simple and portable.

A prompt skill may only require a `skill.json` file.

A tool skill can include its own executable logic.

See:

```text
docs/SKILLS.md
```

for the current skill format and examples.

## Updating Akro

From inside your repository:

```bash
git pull
```

If you have changed local configuration, review your `.env` and config overrides after updating.

## Development

Run the included tests with:

```bash
./tests/smoke.sh
```

You can also check shell syntax manually:

```bash
bash -n chat.sh
bash -n lib/*.sh
```

## Design Philosophy

Akro follows a few simple rules:

1. Local first.
2. Small models first.
3. Small context windows first.
4. Retrieval is better than giant prompts.
5. Tools should be explicit.
6. Slash commands are the main extension interface.
7. Skills should install without modifying Akro itself.
8. Tiny models should handle background organization.
9. Memory should feel simple.
10. Slow operations should always show activity.
11. Bash and JSON are preferred unless something clearly better is needed.
12. The system should remain understandable enough to modify yourself.

## Privacy

Akro is designed primarily around local models and local data.

Your chats, project data, Brain notes, and documents can remain on your machine.

External services are only used when you explicitly enable features that require them, such as Tavily web search.

Review any third-party service's privacy policy before sending sensitive information through it.

## Version

Current major version:

```text
Akro V2
```

V2 focuses on modular skills, projects, long-term memory, searchable knowledge, retrieval for small models, and a more responsive terminal experience.

## License

Add your preferred license to the repository as `LICENSE`.
