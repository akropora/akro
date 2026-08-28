# Akro

Akro is a small terminal chat client for local Ollama models on macOS.

The goal is simple: keep the chat experience good and keep the code easy to read.

## What it does

- chats with Ollama at `127.0.0.1:11434`
- keeps full conversation history
- renders finished answers with Glow
- uses a tiny Neuron model to name chats after the first prompt
- saves each chat as one plain JSON file
- reopens chats with their saved model
- supports simple one-turn prompt skills from `skills.json`
- uses readline-style terminal input

There is no web search, document system, memory layer, system prompt loader, token tracker, or context manager.

## Install

Requirements:

- macOS
- Ollama
- curl
- jq
- Glow

Then run:

```bash
chmod +x install.sh
./install.sh
```

The installer asks which installed Ollama model should be the default, writes that choice to `.config`, creates the Neuron helper model, and installs the `akro` command.

Akro installs to:

```text
~/user/chat/
```

## CLI

```bash
akro
akro list
akro open local-ai-harness
akro help
```

`akro list` prints the filenames of saved chats without `.json`.

## In-chat commands

```text
/skills
/model
/model qwen3:4b
/new
/exit
/bye
/quit
```

## Skills

Skills are simple prompt prefixes stored in `skills.json`.

```text
/concise explain DNS
/step-by-step explain how git rebase works
```

A skill affects only that turn. Skills do not stack.

## Saved chats

Chats live in `conversations/` and stay intentionally plain:

```json
{
  "title": "Local AI Harness",
  "model": "qwen3:4b",
  "messages": [
    {"role": "user", "content": "Hello"},
    {"role": "assistant", "content": "Hi."}
  ]
}
```

When a saved chat is opened, Akro switches to the model stored in that file.

## Files

```text
~/user/chat/
├── conversations/
├── modelfiles/
│   └── neuron
├── system-prompts/
├── chat.sh
├── skills.json
└── .config
```

`system-prompts/` is only a place to keep optional examples for custom Ollama Modelfiles. Akro itself does not load a system prompt.

## Design

Most of Akro lives in `chat.sh` on purpose. There is no framework behind it. The shell script reads the config, handles a few commands, sends conversation history to Ollama, renders the answer, and saves the chat.
