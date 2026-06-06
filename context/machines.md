# Machine-Specific Context

Most context here is shared across every machine (the top-level `AGENTS.md`
routes `context/*.md` everywhere). Context that applies to **one machine only**
lives under `machines/<slug>/` and is loaded only on that machine.

- **Slug** — each machine has a canonical slug (e.g. `laptop`,
  `workstation`), used for its context dir and its private secret bundle
  (`secrets/machines/<slug>.yaml`). Resolve the current machine's slug with
  `scripts/machine-id`. It checks
  `$AGENT_CONTEXT_MACHINE`, then the gitignored repo-root `.machine` marker, then
  falls back to a normalized hostname. Hostnames often don't match the slug, so
  seed `.machine` once per machine: `printf 'laptop\n' > .machine`.
- **Layout** — `machines/<slug>/AGENTS.md` is a thin router (like the top-level
  one); add topic files like `machines/<slug>/context.md` beside it. These files
  are committed plaintext, so every machine can *see* them; only the current
  machine *loads* them.
- **Wiring (per machine)** — the shared `AGENTS.md` stays machine-agnostic
  (committed `@` imports can't vary per machine), so each machine's agent profile
  imports its own router. `scripts/setup` derives the import path from wherever
  this repo is cloned (`<repo>` below), so there's no fixed location assumption:
  - Claude Code — `@<repo>/machines/<slug>/AGENTS.md` in `~/CLAUDE.md`
  - Codex — the same line in `~/.codex/AGENTS.md`
- **Onboarding — run `scripts/setup`** (idempotent). It seeds `.machine`, creates
  `machines/<slug>/` (router + `context.md`), **ingests** any inline content already
  in `~/CLAUDE.md` / `~/.codex/AGENTS.md` into `machines/<slug>/context.md` (backing
  up the profile), and ensures both `@`-imports are present. It also sets up the key
  store ([secrets](secrets.md), `docs/key-stores.md`). Re-running is safe. Then commit & push
  the repo changes (per [meta](meta.md)); the profiles live outside the repo.

**Machine vs identity** — `machines/<slug>/` is purely *context*. Secrets are keyed
by *identity* (an age key, decoupled from any host — see [secrets](secrets.md)). A machine's
private bundle `secrets/machines/<slug>.yaml` is encrypted to the **set of
identities that machine opted into** (`.machine.env` `AGE_IDENTITIES`), so it's
readable by whichever of its keys is present (e.g. local Keychain or a portable
YubiKey). `scripts/setup` handles both axes.
