#!/usr/bin/env bash

set -euo pipefail

ca=$1
certificate=$2
key=$3
client_name=$4

test -r "$ca"
test -r "$certificate"
test -r "$key"
openssl verify -purpose sslclient -CAfile "$ca" -verify_hostname "$client_name" "$certificate" >/dev/null
openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL client : Yes'
openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$client_name"

certificate_public_key=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | openssl dgst -sha256)
key_public_key=$(openssl pkey -in "$key" -pubout -outform DER | openssl dgst -sha256)
test "$certificate_public_key" = "$key_public_key"
