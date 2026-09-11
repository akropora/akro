# Agentic architecture

`/agentic` is a terminal tool skill that completes its own Akro turn.

## Flow

```text
user task
  -> optional earlier skills such as /promptup
  -> Coral Agent
  -> one structured JSON action
  -> Akro validates and executes a curated tool
  -> tool result returns to Coral Agent
  -> repeat
  -> final response
```

The agent does not receive unrestricted Bash. Its model output is constrained to a small JSON action schema. This makes the loop easier to parse, easier to debug, and safer for small models.

## Workspace

Akro captures the working directory from which `akro` or `chat.sh` was started. Agentic treats that directory as its root. An optional `/agentic [subdir]` argument may narrow the workspace, but never expand it.

Blocked paths include `.git`, `.env`, `.ssh`, `..` traversal, absolute paths, and symlink file targets.

## Tools

Read tools:

- `list_files`
- `read_file`
- `search_files`
- selected `run_check` operations

Write tools:

- `write_file`
- `replace_text`
- `make_directory`

Writes ask for confirmation unless `AGENT_CONFIRM_WRITES=0`.

`test_script` may only run scripts under `tests/` and requires confirmation.

## State

Agentic keeps only the original task, a small amount of matching Brain context, and recent tool results in its active model conversation. Tool output is capped. This prevents a 2B model from being buried in a growing transcript.

## Loop protection

- one action per model step
- default maximum 20 steps
- repeated identical actions are blocked
- tool arguments are validated
- final response is required before normal completion
- a finalization request is attempted if the step limit is reached

## Skill protocol extension

V2.2 extends tool skill output. A normal transforming tool still returns:

```json
{"prompt":"transformed prompt"}
```

A tool that completes the entire turn may return:

```json
{
  "complete": true,
  "response": "finished response",
  "model": "coral1.6-agent:latest"
}
```

Completed tool skills must be last in a skill pipeline.
