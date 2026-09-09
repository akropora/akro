# Moving from Akro V1 to V2

V2 changes both the code layout and the data layout.

## V1 assumptions

V1 commonly stored data under something like:

```text
~/projects/ai/brain/
```

with chats, documents, notes, and one Brain index.

## V2 default

V2 uses:

```text
~/.akro/
```

and separates projects from global memory.

## Recommended migration

Do not overwrite V1 data immediately.

1. Keep your V1 folder intact.
2. Start V2 and create the project you want.
3. Copy selected plain-text documents into the V2 project with `/document [path]`.
4. If you want old chats available, copy compatible chat JSON files into the project's `chats/` folder.
5. Run `/learn-all` inside that project.
6. Use `/memory` to promote only truly cross-project notes to global memory.

This keeps old generated notes from becoming permanent global memory by accident.

## Skills

V1 `skills.json` entries should become individual folders under `skills/`.

Prompt skills need only `skill.json`.

Tool skills need `skill.json` plus an executable such as `run.sh`.
