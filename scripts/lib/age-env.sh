# shellcheck shell=bash
# Sourced by secret-get / secret-edit / secret-rekey / setup.
#
# Resolves the age identities a machine can decrypt with, plus an optional
# login-session decrypt cache. Config comes from the gitignored .machine.env at
# the repo root:
#
#   AGE_IDENTITIES   space-separated identity names, primary first
#                    (default: "<machine-slug>-file")
#   AGE_CACHE        1 to enable the session cache (default: 0)
#   AGE_CACHE_KEYCHAIN  dedicated cache keychain name (default: agentkeep)
#
# Each identity's backend/recipient is looked up in identities.yaml (the registry;
# override path with $AGE_REGISTRY). Local key material is found by convention:
#   file     -> registry `file:` path, else the platform default keys.txt
#   keychain -> keychain item `agentkeep-<name>` (or registry `keychain_service:`)
#   se|yubikey -> stub at <age-dir>/<name>.txt (or registry `file:`)
# Encryption recipients come from .sops.yaml, so a bundle is "encrypted to all
# opted-in identities" purely by listing them there — no logic here.

AC_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ac_default_age_key() {
  case "$(uname -s)" in
    Darwin) printf '%s\n' "$HOME/Library/Application Support/sops/age/keys.txt" ;;
    *)      printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt" ;;
  esac
}

ac_sha256() {  # hash stdin -> hex
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else sha256sum | cut -d' ' -f1; fi
}

ac_load_config() {
  local f="$AC_REPO_ROOT/.machine.env"
  if [ -f "$f" ]; then
    # shellcheck disable=SC1090
    . "$f"
  fi
  : "${AGE_CACHE:=0}"
  : "${AGE_CACHE_KEYCHAIN:=login}"   # default: login keychain (no separate passphrase)
  : "${AGE_IDENTITIES:=$("$AC_REPO_ROOT/scripts/machine-id" 2>/dev/null)-file}"
}

# --- identity registry --------------------------------------------------------

ac_registry() { printf '%s\n' "${AGE_REGISTRY:-$AC_REPO_ROOT/identities.yaml}"; }

ac_registry_get() {  # <name> <field> -> value ("" if absent)
  local reg; reg="$(ac_registry)"
  [ -f "$reg" ] || return 0
  yq -e ".identities.\"$1\".$2 // \"\"" "$reg" 2>/dev/null || true
}

# --- key-store identity resolution --------------------------------------------

AC_TMP_IDENTITY=""
ac_cleanup() {
  [ -n "$AC_TMP_IDENTITY" ] && rm -f "$AC_TMP_IDENTITY" 2>/dev/null
  AC_TMP_IDENTITY=""
}

# Emit one identity's age identity lines (key or AGE-PLUGIN-* stub) to stdout.
ac_append_identity() {  # <name> <backend>
  local name="$1" backend="$2" path svc keyb64 key
  case "$backend" in
    file)
      path="$(ac_registry_get "$name" file)"; [ -n "$path" ] || path="$(ac_default_age_key)"
      path="${path/#\~/$HOME}"
      [ -f "$path" ] || { echo "age-env: file identity '$name' key missing: $path" >&2; return 1; }
      cat "$path" ;;
    se|yubikey)
      command -v "age-plugin-$backend" >/dev/null 2>&1 || {
        echo "age-env: age-plugin-$backend not on PATH (identity $name)" >&2; return 1; }
      path="$(ac_registry_get "$name" file)"
      [ -n "$path" ] || path="$(dirname "$(ac_default_age_key)")/$name.txt"
      path="${path/#\~/$HOME}"
      [ -f "$path" ] || { echo "age-env: $backend identity '$name' stub missing: $path" >&2; return 1; }
      cat "$path" ;;
    keychain)
      # item stores the key base64-encoded (security -w returns hex for newlines)
      svc="$(ac_registry_get "$name" keychain_service)"; [ -n "$svc" ] || svc="agentkeep-$name"
      keyb64="$(security find-generic-password -s "$svc" -w 2>/dev/null)" || keyb64=""
      key="$(printf '%s' "$keyb64" | base64 -d 2>/dev/null)"
      [ -n "$key" ] || { echo "age-env: keychain identity '$name' not found (service $svc)" >&2; return 1; }
      printf '%s\n' "$key" ;;
    *) echo "age-env: unknown backend '$backend' for identity '$name'" >&2; return 1 ;;
  esac
}

# Build a combined identity file from AGE_IDENTITIES and point SOPS at it.
# Non-hardware identities go first so a read uses a file/keychain key silently
# instead of triggering a needless Secure Enclave / YubiKey prompt.
ac_prepare_age_env() {
  local ids name backend soft="" hw="" entry
  ids="${AGE_IDENTITIES:-}"
  if [ -z "$ids" ]; then            # nothing configured -> legacy default key file
    if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
      local k; k="$(ac_default_age_key)"; [ -f "$k" ] && export SOPS_AGE_KEY_FILE="$k"
    fi
    return 0
  fi
  for name in $ids; do
    backend="$(ac_registry_get "$name" backend)"; [ -n "$backend" ] || backend="file"
    case "$backend" in se|yubikey) hw="$hw $name:$backend" ;; *) soft="$soft $name:$backend" ;; esac
  done
  AC_TMP_IDENTITY="$(umask 077; mktemp "${TMPDIR:-/tmp}/ac-age.XXXXXX")"
  trap ac_cleanup EXIT
  : > "$AC_TMP_IDENTITY"
  for entry in $soft $hw; do
    name="${entry%%:*}"; backend="${entry##*:}"
    ac_append_identity "$name" "$backend" >> "$AC_TMP_IDENTITY" || return 1
  done
  export SOPS_AGE_KEY_FILE="$AC_TMP_IDENTITY"
  return 0
}

# --- session cache (macOS, opt-in) --------------------------------------------
# Caches the decrypted bundle per file, keyed by a hash of the ciphertext, so
# repeat reads skip the backend prompt. Default store is the LOGIN keychain
# (AGE_CACHE_KEYCHAIN=login): no separate passphrase — it's already unlocked for
# your macOS session, and encrypted at rest with your account password. Set
# AGE_CACHE_KEYCHAIN=<name> to use a dedicated keychain instead (locks on
# sleep/logout/idle; its passphrase becomes an explicit re-login unlock).

ac_cache_kc() {
  case "${AGE_CACHE_KEYCHAIN:-login}" in
    login|"") printf '%s\n' "$HOME/Library/Keychains/login.keychain-db" ;;
    *)        printf '%s\n' "$HOME/Library/Keychains/${AGE_CACHE_KEYCHAIN}.keychain-db" ;;
  esac
}

ac_cache_enabled() {
  [ "${AGE_CACHE:-0}" = "1" ] || return 1
  [ "$(uname -s)" = "Darwin" ] || return 1
  command -v security >/dev/null 2>&1 || return 1
  [ -f "$(ac_cache_kc)" ] || return 1
}

# Ensure the cache keychain is unlocked. Prompts on a TTY; never triggers the
# blocking GUI prompt in non-interactive runs (treats those as unavailable).
ac_cache_unlock() {
  local kc; kc="$(ac_cache_kc)"
  security show-keychain-info "$kc" >/dev/null 2>&1 && return 0
  if [ -t 0 ] || [ -t 2 ]; then
    security unlock-keychain "$kc"
  else
    return 1
  fi
}

ac_cache_get() {  # $1=cipher file -> prints plaintext bundle on hit
  local file="$1" acct kc b64
  kc="$(ac_cache_kc)"
  acct="$(ac_sha256 < "$file")"
  b64="$(security find-generic-password -s agentkeep-cache -a "$acct" -w "$kc" 2>/dev/null)" || return 1
  [ -n "$b64" ] || return 1
  printf '%s' "$b64" | base64 -d 2>/dev/null
}

ac_cache_put() {  # $1=cipher file ; stdin = plaintext bundle
  local file="$1" acct kc b64
  kc="$(ac_cache_kc)"
  acct="$(ac_sha256 < "$file")"
  b64="$(base64 | tr -d '\n')"
  security add-generic-password -U -s agentkeep-cache -a "$acct" -w "$b64" "$kc" >/dev/null 2>&1 || true
}

# Decrypt a secrets file, via cache when enabled, else the backend. Prints
# plaintext to stdout; returns non-zero if the file is absent or undecryptable.
ac_decrypt_file() {  # $1=file
  local file="$1" pt
  [ -f "$file" ] || return 1
  if ac_cache_enabled; then
    ac_cache_unlock || true
    pt="$(ac_cache_get "$file")" && [ -n "$pt" ] && { printf '%s' "$pt"; return 0; }
  fi
  ac_prepare_age_env || return 1
  pt="$(sops --decrypt "$file" 2>/dev/null)" || return 1
  if ac_cache_enabled; then
    printf '%s' "$pt" | ac_cache_put "$file"
  fi
  printf '%s' "$pt"
}
