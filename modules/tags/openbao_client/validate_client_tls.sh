#!/usr/bin/env bash

set -euo pipefail

ca=$1
issuer=$2
certificate=$3
key=$4
client_name=$5

[[ -r "$ca" ]]
[[ -r "$certificate" ]]
[[ -r "$key" ]]

# `openssl verify` only treats the first certificate in $certificate as the
# leaf. Supply the complete presented bundle as untrusted chain input so ACME
# client fullchains can reach the shared cluster CA. TPM-issued clients also
# need their canonical intermediate when it is available; direct-root clients
# remain valid without one.
untrusted_chain=(-untrusted "$certificate")
if [[ -r "$issuer" ]]; then
  untrusted_chain+=(-untrusted "$issuer")
fi
openssl verify -purpose sslclient -CAfile "$ca" "${untrusted_chain[@]}" -verify_hostname "$client_name" "$certificate" >/dev/null
openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL client : Yes'
openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$client_name"

certificate_public_key=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | openssl dgst -sha256)
key_public_key=$(openssl pkey -in "$key" -pubout -outform DER | openssl dgst -sha256)
[[ "$certificate_public_key" == "$key_public_key" ]]
