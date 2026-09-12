# Agentic v4

Akro Agentic uses a deliberately small action protocol.

The selected chat model is the planner, supervisor, judge, and final responder. `AGENT_MODEL` is only an action compiler. It receives one plain-English instruction and returns exactly one physical line.

## Action protocol

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

Escapes inside arguments:

```text
\\   literal backslash
\|   literal pipe
\n   newline
\t   tab
\r   carriage return
```

Akro splits only on unescaped `|`, then decodes escapes. Output containing multiple physical lines is rejected. Invalid output gets one direct repair attempt.

## Permissions

Workspace reads and normal workspace writes run automatically. `DELETE` always asks. `WEB` always asks. Sensitive paths such as `.env`, `.ssh`, `.aws`, and `.git` ask before access. `SHELL` auto-runs only a very small read-only allowlist; everything else asks.

Paths are resolved under the launch workspace. Paths that escape the workspace are blocked in the first v4 implementation.

## Loop protection

Akro blocks the same exact action twice in a row, stops after the same exact action is requested more than three times in one run, and caps Agentic at 12 actions by default.

There is no objective graph, generation counter system, tool registry, or dependency engine in v4.
