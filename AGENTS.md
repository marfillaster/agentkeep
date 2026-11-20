# agentkeep

Single source of truth for context shared across all my coding agents (Claude,
Codex, Antigravity, others) on every machine. Imported by each agent's profile;
never duplicated.

This file is a **thin router**: one `@` line per topic, no content of its own.
Each imported `context/<topic>.md` is itself router-sized: rules that apply to
almost any task, or a stub carrying a topic's hard rules plus a trigger and a
pointer to its full body in `context/ref/<topic>.md`, which is read on demand.
If the `@` lines below show up as bare paths (Codex and Antigravity do not
expand them), read those files now. `[[name]]` anywhere in this repo means
`context/<name>.md`. Paths in pointers are relative to this repo's root, the
directory holding this `AGENTS.md` (your agent profile's import line gives its
absolute path).

@context/meta.md
@context/project-init.md
@context/secrets.md
@context/machines.md
