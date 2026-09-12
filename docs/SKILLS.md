# Skills

Akro v4 ships with four skills:

- `/document [path]`
- `/search`
- `/concise`
- `/agentic [workspace]`

Tool skills run in the user's written order. Prompt modifiers apply after tool preprocessing unless a tool skill completes the turn. `/agentic` completes the turn itself because the selected model is already the supervisor and final writer.
