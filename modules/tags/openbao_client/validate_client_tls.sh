#!/usr/bin/env bash

set -euo pipefail

ca=$1
issuer=$2
certificate=$3
key=$4
client_name=$5

test -r "$ca"
test -r "$certificate"
test -r "$key"

# TPM-issued clients use the canonical per-host intermediate.  ACME clients
# have no TPM CA; their issuer is already part of the certificate bundle and
# remains compatible with the existing direct-root verification path.
untrusted_issuer=()
if [[ -r "$issuer" ]]; then
  untrusted_issuer=(-untrusted "$issuer")
fi
openssl verify -purpose sslclient -CAfile "$ca" "${untrusted_issuer[@]}" -verify_hostname "$client_name" "$certificate" >/dev/null
openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL client : Yes'
openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$client_name"

certificate_public_key=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | openssl dgst -sha256)
key_public_key=$(openssl pkey -in "$key" -pubout -outform DER | openssl dgst -sha256)
test "$certificate_public_key" = "$key_public_key"
