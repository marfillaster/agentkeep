# This Project (agentkeep)

This repo is your single source of truth for shared, cross-agent context. When you
say "add this to preferences", "remember this globally", "always do X", or similar:

1. Record it here — add to the relevant file under `context/`, or create a new topic
   file and route to it from `AGENTS.md`.
2. Keep `AGENTS.md` a thin router (one `@` line per topic). Content goes in
   `context/` files, never inline in `AGENTS.md`.
3. To avoid drift across machines, confirm with me, then commit and push the update
   immediately.
4. Before changing this repo, always fetch and inspect remote state first. Keep
   local work based on the latest `origin/main` unless there are uncommitted local
   changes that need to be preserved.

> This is a template. If you fork it under your own name, the project name above is
> just a label — the rules apply to whatever you call your copy.
