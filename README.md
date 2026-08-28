# Akro

Akro is a tiny terminal chat client for local Ollama models on macOS.

It is built to stay simple. One shell script handles the chat, one JSON file holds prompt skills, and conversations are saved as plain JSON.

## Features

- local Ollama chat at `127.0.0.1:11434`
- full conversation history
- finished responses rendered with Glow
- tiny Neuron model that names chats after the first prompt
- saved conversations
- reopen chats with their original model
- simple one-turn prompt skills
- readline-style terminal input
- lightweight thinking animation

No web search, document system, memory layer, system prompt loader, token tracker, or context manager.

## Requirements

Akro currently supports macOS.

You need:

- [Ollama](https://ollama.com/)
- `curl`
- `jq`
- [Glow](https://github.com/charmbracelet/glow)
- at least one Ollama chat model

With Homebrew:

```bash
brew install jq glow
```

Ollama should already be installed and running.

You should also have at least one model installed:

```bash
ollama list
```

## Install

Run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/akropora/akro/main/install.sh)"
```

The installer will:

1. check the required tools
2. find your installed Ollama models
3. ask which model should be the default
4. install Akro to `~/user/chat`
5. pull `qwen3:0.6b` if needed
6. create the small `neuron` helper model
7. install the `akro` command

If `~/.local/bin` was not already in your PATH, open a new Terminal window after installation or run:

```bash
source ~/.zshrc
```

Then start Akro:

```bash
akro
```

## CLI

Start a new conversation:

```bash
akro
```

List saved conversations:

```bash
akro list
```

Open a saved conversation:

```bash
akro open local-ai-harness
```

Show help:

```bash
akro help
```

You do not need to include `.json` when opening a conversation.

## Chat commands

Inside Akro:

```text
/skills
/model
/model qwen3:4b
/new
/exit
/bye
/quit
```

### `/skills`

Lists every prompt skill in `skills.json`.

### `/model`

Shows the model currently being used.

### `/model <name>`

Switches the current conversation to another installed Ollama model.

Example:

```text
/model qwen3:4b
```

### `/new`

Starts a fresh conversation without leaving Akro.

### `/exit`

Exits Akro.

`/bye` and `/quit` do the same thing.

## Skills

Prompt skills live in:

```text
~/user/chat/skills.json
```

Akro includes:

```json
{
  "concise": "Answer briefly and directly.",
  "step-by-step": "Explain the answer clearly, one step at a time."
}
```

Use a skill at the beginning of your prompt:

```text
/concise explain DNS
```

or:

```text
/step-by-step explain git rebase
```

A skill only changes that one turn.

Skills do not stack.

You can add your own by editing `skills.json`.

For example:

```json
{
  "concise": "Answer briefly and directly.",
  "step-by-step": "Explain the answer clearly, one step at a time.",
  "teacher": "Explain this like a patient teacher using simple examples."
}
```

Then use:

```text
/teacher explain recursion
```

## Conversations

After your first prompt, Neuron gives the chat a short name.

Akro prints the name:

```text
Saved as: local-ai-harness
```

The conversation is stored at:

```text
~/user/chat/conversations/local-ai-harness.json
```

Run:

```bash
akro list
```

to see all saved conversation names.

Then reopen one with:

```bash
akro open local-ai-harness
```

## Conversation format

Conversation files intentionally stay simple:

```json
{
  "title": "Local AI Harness",
  "model": "qwen3:4b",
  "messages": [
    {
      "role": "user",
      "content": "Hello"
    },
    {
      "role": "assistant",
      "content": "Hi."
    }
  ]
}
```

When a conversation is reopened, Akro reads its saved model and automatically switches back to that model.

## Configuration

Your default model is stored in:

```text
~/user/chat/.config
```

The file contains one line:

```text
MODEL=qwen3:4b
```

You can change it manually whenever you want.

This controls the model used when starting a new conversation.

## Files

The GitHub repo is intentionally small:

```text
akro/
├── conversations/
├── modelfiles/
│   └── neuron
├── system-prompts/
├── chat.sh
├── install.sh
├── skills.json
├── .config.example
├── .gitignore
├── LICENSE
└── README.md
```

The installed app only needs:

```text
~/user/chat/
├── conversations/
├── modelfiles/
│   └── neuron
├── chat.sh
├── skills.json
└── .config
```

## Modelfiles and system prompts

The repo also includes folders for example Ollama Modelfiles and system prompts.

These are optional resources for people who want to build custom models for Akro.

Akro itself does not load a system prompt.

## Neuron

Neuron is Akro's tiny helper model.

It is based on:

```text
qwen3:0.6b
```

Neuron is not your main chat model. It currently has one small job:

```text
first prompt
    ↓
Neuron
    ↓
short chat title
    ↓
conversation saved
```

Keeping tiny background jobs separate lets the main chat stay simple.

## How Akro works

Most of Akro lives in `chat.sh` on purpose.

The basic loop is:

```text
input
  ↓
command or skill
  ↓
Ollama
  ↓
thinking animation
  ↓
Glow
  ↓
save
```

That is basically the whole app.

## Philosophy

Akro is intentionally small.

The goal is not to build another large AI framework. It is meant to be a local chat tool that is easy to run, read, change, and understand.

If something can be done simply, Akro should do it simply.