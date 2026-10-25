#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: openbao-provision-cryptfs <openbao_client-host>" >&2
  exit 2
fi

host=$1
case "$host" in
@approvedHosts@) ;;
*)
  echo "refusing to provision unapproved OpenBao client host: $host" >&2
  exit 2
  ;;
esac

if [[ -z ${BAO_TOKEN:-} ]]; then
  if [[ -t 0 ]]; then
    printf 'OpenBao token: ' >&2
    if ! IFS= read -r -s BAO_TOKEN; then
      BAO_TOKEN=${BAO_TOKEN:-}
    fi
    printf '\n' >&2
  else
    IFS= read -r BAO_TOKEN || BAO_TOKEN=${BAO_TOKEN:-}
  fi
fi

if [[ -z ${BAO_TOKEN:-} ]]; then
  echo 'BAO_TOKEN must be set or supplied as a nonempty token line' >&2
  exit 2
fi
export BAO_TOKEN

export BAO_ADDR="@api@"
export BAO_CACERT="@ca@"
export BAO_CLIENT_CERT="@certificate@"
export BAO_CLIENT_KEY="@key@"

bao status >/dev/null

if ! bao auth list -format=json | jq -e 'has("cert/")' >/dev/null; then
  bao auth enable cert
fi

mount_type=$(bao secrets list -format=json | jq -r '."cryptfs/".type // empty')
if [[ -z "$mount_type" ]]; then
  bao secrets enable -path=cryptfs -version=2 kv
elif [[ "$mount_type" != kv ]]; then
  echo "cryptfs already exists but is not a KV mount" >&2
  exit 1
fi

mount_version=$(bao secrets list -format=json | jq -r '."cryptfs/".options.version // empty')
if [[ "$mount_version" != 2 ]]; then
  echo "cryptfs must be a KV v2 mount" >&2
  exit 1
fi

if ! bao kv get -mount=cryptfs "$host/key" >/dev/null 2>&1; then
  client_key_file=$(mktemp)
  trap 'rm -f -- "$client_key_file"' EXIT
  chmod 600 "$client_key_file"
  openssl rand -base64 48 >"$client_key_file"
  bao kv put -mount=cryptfs "$host/key" key=@"$client_key_file"
fi

bao policy write "cryptfs-$host" - <<POLICY
path "cryptfs/data/$host/key" {
  capabilities = ["read"]
}
POLICY

bao write "auth/cert/certs/cryptfs-$host" \
  certificate=@"$BAO_CACERT" \
  allowed_dns_sans="$host.node.@domain@" \
  policies="cryptfs-$host" \
  token_ttl=1h \
  token_max_ttl=4h
