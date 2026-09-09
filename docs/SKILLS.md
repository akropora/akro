# Akro V2 Skills

## Goal

Adding a skill should mean adding a folder, not editing Akro core.

Akro scans:

```text
skills/*/skill.json
```

Any valid skill is detected automatically.

## Prompt skill

A prompt skill only changes instructions sent to the model.

Example:

```text
skills/concise/skill.json
```

```json
{
  "name": "concise",
  "type": "prompt",
  "syntax": "/concise",
  "description": "Give a short, direct answer.",
  "instruction": "Answer briefly and directly."
}
```

Use it like:

```text
Explain this /concise
```

## Tool skill

A tool skill runs an executable.

```json
{
  "name": "search",
  "type": "tool",
  "syntax": "/search",
  "description": "Search the web.",
  "entrypoint": "run.sh",
  "activity": "searching"
}
```

The executable receives the current user prompt on standard input.

For skills invoked as:

```text
/document [~/notes/file.txt]
```

Akro exposes the bracket argument as:

```bash
$AKRO_SKILL_ARG
```

## Tool output contract

A tool prints one JSON object to standard output:

```json
{
  "prompt": "the transformed prompt for the main model",
  "notice": "optional short status message"
}
```

Anything written to standard error is treated as an error if the tool exits nonzero.

## Activity indicator

Akro runs tool skills as child processes and animates the value of `activity` while the tool is working.

The tool does not need to implement its own spinner.

## Skill stacking

Skills can be stacked:

```text
Fix this /plsfix /concise
```

Tool skills run in the user's written order.

Prompt skills are applied after tool work. This keeps instructions such as `/concise` from becoming part of a web search query.

## Skill naming rules

Use simple folder and skill names:

```text
lowercase
letters
numbers
hyphens
underscores
```

The folder name should match the manifest `name`.

## Recommended rule

Keep a skill small. If a skill needs a whole framework to work, it probably belongs outside Akro core and should expose a small command interface back into Akro.
