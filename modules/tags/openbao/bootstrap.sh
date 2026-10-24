#!/usr/bin/env bash

set -euo pipefail

export BAO_ADDR="@apiAddress@"
export BAO_CACERT="@tlsCa@"
export BAO_CLIENT_CERT="@tlsCertificate@"
export BAO_CLIENT_KEY="@tlsKey@"
: "${BAO_TOKEN:?/run/openbao/bootstrap.env must define BAO_TOKEN}"

bao status >/dev/null

if ! bao auth list -format=json | jq -e 'has("cert/")' >/dev/null; then
  bao auth enable cert
fi

if ! bao secrets list -format=json | jq -e '."gocryptfs/".type == "kv"' >/dev/null; then
  bao secrets enable -path=gocryptfs -version=2 kv
fi

@clientProvisioning@
