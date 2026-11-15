# This Project (agentkeep)

This repo is your single source of truth for shared, cross-agent context. When you
say "add this to preferences", "remember this globally", "always do X", or similar:

1. Record it here — add to the relevant file under `context/`, or create a new topic
   and route to it from `AGENTS.md`.
2. Keep every always-loaded file router-sized. `AGENTS.md` holds one `@` line per
   topic and no content. Each `context/<topic>.md` it imports is either a short
   rule set that applies to almost any task, or a stub (the topic's hard rules, a
   specific trigger, and a backticked pointer to the full body in
   `context/ref/<topic>.md`). The test for what stays in the stub: would an agent
   working in an unrelated repo need it before it knows the task touches the
   topic? Detail, recipes, and examples go in the `ref/` body. Never write
   `@path` in prose (Claude Code would expand it); backtick paths instead. The
   same applies to `machines/<slug>/context.md`, with bodies in
   `machines/<slug>/ref/`.
3. To avoid drift across machines, confirm with me, then commit and push the update
   immediately.
4. Before changing this repo, always fetch and inspect remote state first. Keep
   local work based on the latest `origin/main` unless there are uncommitted local
   changes that need to be preserved.

> This is a template. If you fork it under your own name, the project name above is
> just a label — the rules apply to whatever you call your copy.
