#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: tpm-tls-sign <machine>" >&2
  exit 2
fi

machine=$1
work="$(mktemp -d "/tmp/tpm-tls-sign-$machine.XXXXXX")"
root_key="$work/root-ca.key"
csr="$work/@tpmCaCsrFile@"
crt="$work/@tpmCaCertificateFile@"
key="$work/@tpmCaKeyFile@"
serial="$work/@tpmCaSerialFile@"

repo="${CLAN_DIR:-$(git rev-parse --show-toplevel)}"
root_crt="$repo/vars/shared/@clusterCaGenerator@/@clusterCaCertificateFile@/value"
if [[ ! -s "$root_crt" ]]; then
  echo "missing root CA certificate: $root_crt" >&2
  exit 1
fi

cleanup() {
  rm -f "$root_key"
}
trap cleanup EXIT

# Avoid PTY line-ending conversion while fetching files through clan ssh.
clan ssh "$machine" -c base64 -w0 @tpmCaCsr@ |
  base64 -d > "$csr"
clan ssh "$machine" -c base64 -w0 @tpmCaKey@ |
  base64 -d > "$key"

clan vars get "$machine" @tpmGenerator@/@tpmCaKeyFile@ > "$root_key"

openssl x509 \
  -req \
  -in "$csr" \
  -CA "$root_crt" \
  -CAkey "$root_key" \
  -CAserial "$serial" \
  -CAcreateserial \
  -out "$crt" \
  -days 1825 \
  -sha256 \
  -extfile @intermediateCaExt@

openssl verify -CAfile "$root_crt" "$crt"

clan vars set "$machine" @tpmGenerator@/@tpmCaKeyFile@ < "$key"
clan vars set "$machine" @tpmGenerator@/@tpmCaCertificateFile@ < "$crt"
clan vars fix "$machine"

echo "stored @tpmGenerator@/@tpmCaKeyFile@ and @tpmGenerator@/@tpmCaCertificateFile@ for $machine"
echo "temporary files kept in $work"
