#!/usr/bin/env bash

set -euo pipefail

key=@tpmCaKey@
csr=@tpmCaCsr@

if [[ -e "$key" ]]; then
  echo "$key already exists" >&2
  exit 1
fi

install -d -m 0700 @tpmDirectory@
stpm-keygen -o "$key"

OPENSSL_CONF=@opensslConf@ \
SIMPLE_TPM_PK11_CONFIG=@simpleTpmPk11Conf@ \
  openssl req \
    -new \
    -engine pkcs11 \
    -keyform engine \
    -key "@pkcs11OpenSslUri@" \
    -subj "/CN=TLS CA: @commonName@" \
    -out "$csr"

echo "wrote $key"
echo "wrote $csr"
