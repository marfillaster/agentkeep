# agentkeep

Single source of truth for context shared across all my coding agents (Claude,
Codex, others) on every machine. Imported by each agent's profile; never
duplicated.

This file is a **thin router** — it holds no content of its own. Each topic lives
in its own file under `context/` and is routed below. To add a topic, create a
file and add one `@` line here. Keep it thin.

@context/meta.md
@context/project-init.md
@context/secrets.md
@context/machines.md
