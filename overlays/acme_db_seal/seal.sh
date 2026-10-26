#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: acme-db-seal <machine>" >&2
  exit 2
fi

machine=$1

work="$(mktemp -d "/tmp/acme-db-seal-$machine.XXXXXX")"
sealed="$work/key.sealed"
vars_list="$work/vars.list"

cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT

if ! clan vars list "$machine" > "$vars_list"; then
  echo "Failed to list variables for $machine; refusing to create acme-db/key.sealed" >&2
  exit 1
fi

if grep -q '^acme-db/key\.sealed:' "$vars_list"; then
  echo "Refusing to overwrite existing acme-db/key.sealed for $machine" >&2
  exit 1
fi

# shellcheck disable=SC2016
clan ssh "$machine" -c bash -c '
  set -euo pipefail
  if [[ -e @acmeGocryptfsConfig@ ]]; then
    echo "Refusing to seal an initialized ACME database: @acmeGocryptfsConfig@" >&2
    exit 1
  fi
  install -d -m 0700 @acmeDirectory@
  tmp="$(mktemp -d @acmeDirectory@/acme-db-seal.XXXXXX)"
  cleanup_remote() {
    rm -rf "$tmp"
  }
  trap cleanup_remote EXIT

  head -c 48 /dev/urandom | base64 -w0 > "$tmp/key"
  tpm_sealdata -z -i "$tmp/key" -o "$tmp/key.sealed"
  # Avoid PTY line-ending conversion while fetching files through clan ssh.
  base64 -w0 "$tmp/key.sealed"
' | base64 -d > "$sealed"

clan vars set "$machine" acme-db/key.sealed < "$sealed"
clan vars fix "$machine"

echo "Stored acme-db/key.sealed for $machine"
