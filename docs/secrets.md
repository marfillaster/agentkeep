# Secret management (SOPS + age)

Secrets are stored **encrypted** in `secrets/secrets.yaml` and committed to Git. Encryption uses [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) recipients. Each machine/agent has its own age key pair; the **public** recipient goes in `.sops.yaml`, the **private** key never leaves the machine and is never committed.

## Install

macOS (Homebrew):

```bash
brew install sops age yq shellcheck
```

Linux:

```bash
# Debian/Ubuntu
sudo apt-get install -y age
# sops: install the latest release binary (apt's version is often old)
SOPS_VER=v3.13.1
curl -sSLo /usr/local/bin/sops \
  "https://github.com/getsops/sops/releases/download/${SOPS_VER}/sops-${SOPS_VER}.linux.amd64"
sudo chmod +x /usr/local/bin/sops

# Arch
sudo pacman -S sops age

# Fedora
sudo dnf install sops age
```

This repo's `secret-get` also needs [`yq`](https://github.com/mikefarah/yq) (v4). `shellcheck` is optional but recommended for validating the helper scripts.

## Quick start: `scripts/setup`

`scripts/setup` does the whole onboarding idempotently — deps, machine slug, the
`machines/<slug>/` context dir + agent-profile rewiring (ingesting any inline
content), then the identity (key store), registry, recipient, and optional cache.
Prefer it over the manual steps below.

```bash
scripts/setup                                # file identity, default everything
scripts/setup --store keychain --cache       # new host-bound key (name auto = <slug>-keychain)
scripts/setup --identity yubikey-5c --store yubikey --install   # new portable key (first time)
scripts/setup --identity yubikey-5c          # reuse an existing identity (store read from registry)
scripts/setup --dry-run                      # preview without changing anything
```

Flags: `--identity NAME` is *which* key (its registry label); `--store BACKEND` is
*where* the key lives (file/keychain/se/yubikey). Pass `--store` only when creating
a new identity — for a host-bound key the name defaults to `<slug>-<store>`, and for
an existing identity the backend is read from the registry.

## Identities & the registry

An **identity** is an age keypair (a recipient) — the unit for secrets, independent
of any host (a portable YubiKey is one identity usable from any machine). Identities
live in the public registry **`identities.yaml`** (name → recipient, backend,
portable, host). A machine lists the ones it uses in its gitignored `.machine.env`
(`AGE_IDENTITIES="name1 name2"`). `scripts/identities` lists them and checks that
the registry agrees with `.sops.yaml`. Key stores (file / Keychain / Secure Enclave
/ YubiKey) and cached reads: see **`docs/key-stores.md`**. The sections below
document the underlying mechanics that `setup` automates.

## Where the private key lives

The helper scripts use the age private key from the platform-native default
location when `$SOPS_AGE_KEY_FILE` is unset:

| Platform | Default `keys.txt` location |
| --- | --- |
| macOS | `~/Library/Application Support/sops/age/keys.txt` |
| Linux | `~/.config/sops/age/keys.txt` (or `$XDG_CONFIG_HOME/sops/age/keys.txt`) |
| Windows | `%AppData%\sops\age\keys.txt` |

Put the key in your platform's default above and the repo helpers will use it.
To use a non-default path, point `$SOPS_AGE_KEY_FILE` at it.

## Generate a machine age key

Each machine generates its own key **once**, into the default location for its
platform. macOS:

```bash
mkdir -p "$HOME/Library/Application Support/sops/age"
age-keygen -o "$HOME/Library/Application Support/sops/age/keys.txt"
chmod 600 "$HOME/Library/Application Support/sops/age/keys.txt"
```

Linux:

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

## Get the public recipient

```bash
# macOS — adjust the path to your platform's default (see the table above)
age-keygen -y "$HOME/Library/Application Support/sops/age/keys.txt"
# -> age1........................................................
```

The line printed (`age1...`) is the **public recipient**. Share this; never share `keys.txt`.

## Add a new machine recipient

Use this flow when bootstrapping a new machine that cannot decrypt
`secrets/secrets.yaml` yet.

1. On the new machine, generate its key and print its recipient (above).
2. On the new machine, fetch first, then add the recipient to `.sops.yaml`
   under the `age:` list, with a comment naming the machine:

   ```yaml
   creation_rules:
     - path_regex: secrets/.*\.ya?ml$
       age:
         - age1existing...   # laptop (added 2026-06-06)
         - age1newmachine... # ken-linux (added 2026-06-07)
   ```
3. Commit and push `.sops.yaml`.
4. On an existing machine that can already decrypt, pull the update:

   ```bash
   git pull --rebase
   ```

5. Rekey so the encrypted file can be opened by the new recipient:

   ```bash
   scripts/secret-rekey
   ```
6. Commit and push `secrets/secrets.yaml`.
7. On the new machine, pull and verify decrypt access without printing a secret:

   ```bash
   git pull --rebase
   scripts/secret-get EXAMPLE_API_TOKEN >/dev/null
   ```

## Rekey existing secrets

After any change to the recipient list in `.sops.yaml`:

```bash
scripts/secret-rekey   # = sops updatekeys secrets/secrets.yaml
```

This re-wraps the data key for the current recipients **without** changing the secret values.

## Read a single secret

```bash
scripts/secret-get EXAMPLE_API_TOKEN
```

Decrypts in memory and prints only that value. Pipe it directly into tools that can read from stdin, config files, or environment variables. Avoid putting secret values directly in command arguments because they can appear in process listings and terminal history.

For tools that require a header, prefer an fd-backed config or another stdin/config mechanism instead of embedding the value in the command line:

```bash
curl --config <(
  printf 'header = "Authorization: Bearer %s"\n' "$(scripts/secret-get EXAMPLE_API_TOKEN)"
) https://api.cloudflare.com/...
```

## Keys and environment variables

Every value here is an environment-variable secret, and each key is named after
the env var it populates (`key == $VAR`). Load one into the environment for a
consumer that expects it:

```bash
export EXAMPLE_API_TOKEN="$(scripts/secret-get EXAMPLE_API_TOKEN)"
```

If a key ever needs to map to a differently-named env var, record that mapping in
`.sops.yaml` (SOPS strips comments from the encrypted file, so it can't live
there).

## Edit secrets

```bash
scripts/secret-edit   # opens SOPS in $EDITOR, re-encrypts on save
```

## Per-machine private bundle

The shared `secrets/secrets.yaml` is readable by every identity. For secrets that
shouldn't be, use this machine's bundle `secrets/machines/<slug>.yaml`. Its
`.sops.yaml` rule lists the **identities this machine opted into**, so SOPS encrypts
the bundle to all of them at once — readable by whichever device is present (e.g.
the local Keychain key *or* your YubiKey), not by other machines' keys.

`<slug>` is the canonical machine name printed by `scripts/machine-id` (seed the
gitignored `.machine` marker once: `printf 'laptop\n' > .machine`).

Edit the bundle (SOPS makes the file on first save, encrypted to all recipients in
its rule):

```bash
scripts/secret-edit --machine        # alias: --key
```

Read with the normal command — it checks the bundle first, then the shared file, so
a bundle value overrides a shared one of the same name:

```bash
scripts/secret-get SOME_LOCAL_TOKEN
```

The encrypted bundle **is** committed. Check how many identities it's encrypted to:

```bash
grep -c 'recipient:' secrets/machines/laptop.yaml   # = number of opted-in identities
```

`scripts/secret-rekey` re-encrypts the shared file plus this machine's bundle to the
current opted-in recipient set. (A machine can only rekey bundles it can decrypt.)

### Encrypting a bundle to more than one identity

Opt the machine into multiple identities and SOPS encrypts the bundle to all of
them — e.g. a Keychain key for local reads and a YubiKey for portability. Run
`scripts/setup --identity <name> --store <backend>` for each; it registers the
identity and prints the `.sops.yaml` additions (the bundle rule **and** the shared
rule), then `scripts/secret-rekey`. The rule ends up like:

```yaml
creation_rules:
  - path_regex: secrets/machines/laptop\.ya?ml$    # this machine's bundle
    age:
      - age1...keychain   # laptop-keychain
      - age1yubikey1...    # yubikey-5c (portable)
  - path_regex: secrets/.*\.ya?ml$                       # shared — keep last
    age: [ ... all identities ... ]
```

## Rotate a compromised machine

If a machine's private key may be exposed:

1. Remove that machine's recipient line from `.sops.yaml`.
2. Rekey so it can no longer decrypt going forward:

   ```bash
   scripts/secret-rekey
   ```
3. **Rotate the secret values themselves** — the old ciphertext (and any clone of it) is still decryptable by the leaked key in Git history. Generate new tokens at each provider, then `scripts/secret-edit` to store the new values.
4. Commit and push.
