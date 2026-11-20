# agentkeep

Portable, shared context for coding agents (Claude Code, Codex, Antigravity, and
others) across all your machines. [`AGENTS.md`](./AGENTS.md) is the single source
of truth; each agent's profile imports it instead of holding its own copy.

It's a **template** — clone it, run `scripts/setup`, and make it yours. Two
subsystems ship together:

- **Context router** — a thin `AGENTS.md` that `@`-imports one router-sized file per
  topic from `context/` (full topic bodies live in `context/ref/` and are read on
  demand), plus per-machine context under `machines/<slug>/` loaded only on that
  machine.
- **Secrets** — SOPS + age encrypted secrets you can commit, read through
  `scripts/secret-get`, with multi-identity support and per-machine private bundles.

## Layout

| File | Purpose |
| --- | --- |
| `AGENTS.md` | Thin **router** — one `@` import per topic, no inline content. |
| `context/*.md` | One always-loaded file per topic: short rules, or a stub with the topic's hard rules, a trigger, and a pointer to its body. Add a file, route to it from `AGENTS.md`. |
| `context/ref/*.md` | Full topic bodies, read on demand when a stub's trigger fires. Not imported. |
| `machines/<slug>/` | Per-machine context, loaded **only** on that machine via its agent profile: thin router + router-sized `context.md`, with full topic bodies in `ref/`. Created by `scripts/setup`. |
| `secrets/secrets.yaml` | SOPS+age **encrypted** shared secrets (all identities), safe to commit. Read via `scripts/secret-get`. Created via `scripts/secret-edit`. |
| `secrets/secrets.yaml.example` | Plaintext example showing the `key == $ENV_VAR` convention. |
| `secrets/machines/<slug>.yaml` | A machine's private bundle, encrypted to the identities it opted into. Edit via `scripts/secret-edit --machine`. |
| `identities.yaml` | Public registry of age identities (name → recipient, backend, portable). |
| `.sops.yaml` | age recipients per rule (shared + per-machine bundle); mirrors `identities.yaml`. |
| `scripts/setup` | Idempotent onboarding (deps, slug/context/profiles, identity/key store, recipient, cache). |
| `scripts/secret-*` | `secret-get` / `secret-edit` / `secret-rekey`. |
| `scripts/identities` | Lists identities and checks registry ↔ `.sops.yaml` agree. |
| `scripts/machine-id` | Prints the current machine's canonical slug (context axis). |
| `scripts/lib/age-env.sh` | Sourced: resolves a machine's identities (file/keychain/SE/YubiKey) + session cache. |
| `docs/secrets.md` | Full secret-management how-to (install, keys, rotation). |
| `docs/key-stores.md` | Key-store options + cached-read / unlock-on-re-login behavior. |
| `CLAUDE.md` | `@AGENTS.md` — so this repo works as a Claude project too. |

To add a preference: drop it in the relevant `context/*.md` or `context/ref/*.md` (or
create a new topic file + add one `@` line to `AGENTS.md`; long bodies go in
`context/ref/` behind a stub), then commit and push so other machines stay
in sync.

## Getting started

This is a GitHub **template repository**. Click **Use this template ▸ Create a new
repository** to make your own copy (public or private) under your account — that
becomes *your* single source of truth. Then clone it anywhere and run setup:

```sh
git clone https://github.com/<you>/<your-repo>.git
cd <your-repo> && scripts/setup          # add --store/--cache as desired
```

> Just kicking the tires? Clone this repo directly instead:
> `git clone https://github.com/marfillaster/agentkeep.git`. To make it yours
> later, repoint `origin` at your own remote (or start over from the template).

`scripts/setup` is idempotent — it seeds the machine slug, provisions the key
store, ensures the recipient/cache, creates `machines/<slug>/`, and wires the
agent profiles (`~/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/AGENTS.md`),
ingesting any inline content already there. The import paths it writes are derived
from wherever you cloned the repo, so there's no fixed location assumption. Re-run
it any time. Preview with `scripts/setup --dry-run`.

Doing it by hand instead, point each agent's profile at the repo (`<repo>` is your
clone path):

- **Claude Code** — `@<repo>/AGENTS.md` and `@<repo>/machines/<slug>/AGENTS.md` in
  `~/CLAUDE.md`
- **Codex** — the same two lines in `~/.codex/AGENTS.md`
- **Antigravity (`agy`)** — `@[agentkeep](<repo>/AGENTS.md)` and
  `@[agentkeep-machine](<repo>/machines/<slug>/context.md)` in `~/.gemini/AGENTS.md`
  (Antigravity's `@[label](path)` inlines one level deep, so the machine entry
  targets `context.md` directly)

(The shared `AGENTS.md` is machine-agnostic.) See `context/ref/machines.md`,
`docs/secrets.md`, and `docs/key-stores.md`.

## Updating

Edit the relevant `context/*.md` file, or add a new topic file and route it from
`AGENTS.md`. Commit and push immediately so other machines and agents do not
drift; pull on each machine to sync.
