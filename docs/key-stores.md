# Key stores & the identity model

## Identities, not machines

An **identity** is an age keypair = a recipient (the `age1…` in `.sops.yaml`). It's
the unit for secrets, and it's independent of any host: a host-bound key
(file/Keychain/Secure Enclave) lives on one machine; a portable YubiKey works on
any machine. Identities are listed in the public registry **`identities.yaml`**
(name → recipient, backend, portable, host); `scripts/identities` lists them and
warns if they drift from `.sops.yaml`. A **machine** declares the identities it
uses in its gitignored `.machine.env` (`AGE_IDENTITIES="name1 name2"`, primary
first) and may hold several at once — e.g. its Keychain key *and* a YubiKey.

A backend is just *where an identity's private key lives*. The recipient is
backend-agnostic — SOPS only cares about the `age1…` string. `scripts/secret-get` /
`secret-edit` / `secret-rekey` resolve a machine's identities through
`scripts/lib/age-env.sh` (trying non-hardware keys first, so reads don't trigger
needless prompts). `scripts/setup --identity NAME --store BACKEND` provisions them.

A machine's private bundle `secrets/machines/<slug>.yaml` is encrypted to **all**
its opted-in identities at once (its `.sops.yaml` rule lists them), so it's readable
by whichever device is present — only public recipients are needed to encrypt.

## Backends

| Store | `backend` | Protection | Unlock prompt | Hardware-bound | Portable | SOPS | Platform |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Plaintext file | `file` (default) | file perms (600) only | none | no | copyable | native | all |
| macOS Keychain | `keychain` | encrypted at rest; key still loads into RAM to decrypt | keychain unlock (login pw / Touch ID) | no | export-only | via temp identity | macOS |
| Secure Enclave | `se` | key generated in & never leaves the SE | Touch ID **per decrypt** | **yes** (this Mac) | no | via plugin¹ | macOS (M-series / T2) |
| YubiKey (PIV) | `yubikey` | key never leaves the token | PIN + optional touch | yes (the token) | **yes** (carry the key) | via plugin | macOS/Linux/Win² |
| Linux keyring | (documented³) | Secret Service / kernel keyring | desktop keyring unlock | no | no | via plugin | Linux |

¹ SOPS rejects `age1se1…` recipients (getsops/sops#1803). Generate the SE key's
recipient in **YubiKey/piv-p256 form** (`age1yubikey1…`) — SOPS accepts that, and
the same SE key decrypts it. Keep `age-plugin-se` on `PATH` for decryption.
² YubiKey on Linux needs `pcscd` (`apt install pcscd` / `dnf install pcsc-lite`).
³ Linux: `age-plugin-keystore` (X25519 keys in the Secret Service via D-Bus) or
keep `AGE_STORE=file` with the file on an encrypted home. Not yet wired into setup.

## Cached reading (`AGE_CACHE=1`)

Hardware backends prompt on **every** decrypt (the SE/YubiKey don't cache across
processes). The opt-in session cache fixes that: the decrypted bundle is cached
(keyed by a hash of the ciphertext, so it self-invalidates when secrets change), so
repeat reads skip the backend prompt.

**Default store: your login keychain** (`AGE_CACHE_KEYCHAIN=login`). No separate
passphrase to set or forget — it's already unlocked for your macOS session and
encrypted at rest with your account password. Reads within a session are silent;
the cache rides on your normal macOS login.

**Stricter opt-in: a dedicated keychain** (`AGE_CACHE_KEYCHAIN=<name>`, created by
`scripts/setup --cache` with a passphrase). It locks on sleep / logout / 1h idle
and isn't auto-unlocked, so the first read after re-login prompts for its passphrase
— an explicit "unlock on re-login" gate. More secure, but a passphrase you must
remember.

Trade-off either way: the cache holds **plaintext** at the keychain's trust level,
and once populated, reads don't re-hit the hardware until the ciphertext changes.
It's **off by default** and opt-in. macOS only.

## Choosing

- **`file`** — simplest; fine when the home dir is already FileVault-encrypted and
  the machine is single-user. Today's default.
- **`keychain`** — better at-rest protection, no extra tooling, clean cache story.
  Key is still software (loads into RAM to decrypt).
- **`se`** — strongest on a Mac you don't move; Touch ID gated; key unexportable.
  Pair with `AGE_CACHE=1` to avoid Touch ID on every read.
- **`yubikey`** — strongest *portable* option; the same token decrypts on any of
  your machines (one recipient, not one-per-machine). PIN + touch.

## Adding an identity to a machine (e.g. file → Keychain/SE/YubiKey)

Each new backend is a **new identity** (new recipient). You don't have to retire the
old one — a machine can use several at once, and its bundle can be encrypted to all
of them. To add one:

1. `scripts/setup --identity <name> --store <backend>` → generates the key, prints
   the recipient, registers it (`identities.yaml`), and adds it to `AGE_IDENTITIES`.
2. Add the recipient to `.sops.yaml` — the machine's bundle rule **and** the shared
   rule (setup prints the exact lines); commit/push.
3. `scripts/secret-rekey` on a machine that can decrypt → re-encrypts to the full
   opted-in set; push.
4. Verify: `scripts/secret-get EXAMPLE_API_TOKEN >/dev/null`.
5. To *retire* the old identity: remove its recipient from `.sops.yaml` +
   `identities.yaml`, `scripts/secret-rekey`, push. If the old key was a plaintext
   `file` key it remains in git history — **rotate the secret values**
   (`scripts/secret-edit`); see "Rotate a compromised machine" in `docs/secrets.md`.

### Portable YubiKey across machines

Provision once (`scripts/setup --identity yubikey-5c --store yubikey`), add its
recipient, rekey. On every other machine, just `scripts/setup --identity yubikey-5c`
(already in the registry): it writes the local identity stub from the plugged key
and adds it to that machine's `AGE_IDENTITIES` — no new key, no rekey. Now your
YubiKey decrypts shared secrets anywhere it's plugged in.

## Install (macOS)

```bash
brew install sops age yq              # core
brew install age-plugin-se            # Secure Enclave
brew install age-plugin-yubikey       # YubiKey (also: `brew install ykman`)
```
