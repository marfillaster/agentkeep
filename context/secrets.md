# Secrets (SOPS + age)

Hard rules, always: never print a secret value (stdout, transcript, commit, PR, recorded command args; pipe it into the consumer). Never cat, decrypt, or parse `secrets/*.yaml` directly, and never write or commit decrypted output. To get a credential, use the env var named after the key if it is set, else this repo's `scripts/secret-get <KEY>`.

Read this repo's `context/ref/secrets.md` before editing, adding, or rekeying a secret, touching `.sops.yaml`/`identities.yaml`, or setting up a key store.
