# Secrets (SOPS + age)

Secrets live encrypted in `secrets/secrets.yaml` (SOPS + age). Rules for all agents:

- **Reading a secret: check the environment first, then `scripts/secret-get`.** Every key is named after its env var (key == `$VAR`), so if `$VAR` is already exported, use that value directly and skip decryption — prefer the env var over reaching for the script. Only when it's unset, fall back to `scripts/secret-get <KEY>` (e.g. `scripts/secret-get EXAMPLE_API_TOKEN`), which reads this machine's private bundle then the shared file. Add `--identity NAME` to force one specific key and bypass the cache (e.g. to verify a YubiKey actually decrypts). Either way, never cat, decrypt, or parse the `secrets/*.yaml` files directly.
- **Never print a secret value** to stdout logs, the terminal transcript, commit messages, PRs, or command arguments that get recorded. Pipe it straight into the consuming command.
- **Never commit decrypted output.** No `sops -d > file`, no `.decrypted`/`.plaintext`/`.env` files. `.gitignore` guards these — don't override it.
- **Never modify `.sops.yaml` recipients or `identities.yaml`** (add/remove identities) unless explicitly asked — use `scripts/setup --identity`, which is the asked-for path.
- **Edit secrets only via `scripts/secret-edit`** (opens SOPS, re-encrypts on save). Never hand-edit the ciphertext.
- **After any recipient change**, run `scripts/secret-rekey` so files re-encrypt to the current recipient set.
- **Onboard / repair a machine with `scripts/setup`** (idempotent): deps, slug, context dir, profile rewiring, identity/key store, registry + recipient, optional cache. Don't hand-do those steps.

## Identities vs machines

An **identity** is an age keypair (a recipient) — the unit for secrets. A **machine** is a host — the unit for context ([[machines]]). They're independent: a host-bound key (file/Keychain/Secure Enclave) lives on one host; a portable YubiKey works on any host. Identities are listed in the public registry `identities.yaml` (`scripts/identities` lists them + checks `.sops.yaml` drift). A machine declares the identities it uses in the gitignored `.machine.env` (`AGE_IDENTITIES="name1 name2"`, primary first); `scripts/secret-get` resolves them via `scripts/lib/age-env.sh`, trying non-hardware keys first so reads don't trigger needless Touch ID / YubiKey prompts. Key store + cache: see `docs/key-stores.md`.

## Per-machine private bundle

Secrets not meant for everyone live in this machine's bundle `secrets/machines/<slug>.yaml`, encrypted to the **set** of identities this machine opted into (its `.sops.yaml` rule) — so it's readable by whichever device is present (e.g. local Keychain *or* your YubiKey). The shared `secrets/secrets.yaml` is encrypted to every identity.

- **Read** with the same `scripts/secret-get <KEY>` — checks this machine's bundle first, then shared (bundle overrides). No flag.
- **Edit** the bundle with `scripts/secret-edit --machine` (alias `--key`); SOPS encrypts to all recipients in its rule at once. Plain `scripts/secret-edit` edits the shared file.
- **Rekey** — `scripts/secret-rekey` re-encrypts the shared file + this machine's bundle to the current opted-in recipient set.
- Encrypted bundles **are** committed; the gitignored `.machine` / `.machine.env` are not.

Human how-to (identities, key stores, adding machines, rotation): `docs/secrets.md`, `docs/key-stores.md`.
