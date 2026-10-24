#!/usr/bin/env bash

set -euo pipefail

ca=$1
issuer=$2
certificate=$3
key=$4
api_name=$5
cluster_name=$6

test -r "$ca"
test -r "$issuer"
test -r "$certificate"
test -r "$key"
# openssl verify treats the first PEM certificate in $certificate as the leaf;
# it does not automatically use later PEM certificates as untrusted issuers.
# Keep the shared cluster CA as the sole trust anchor and explicitly provide
# the host TPM intermediate from its canonical PKI location.
openssl verify -purpose sslserver -CAfile "$ca" -untrusted "$issuer" -verify_hostname "$api_name" "$certificate" >/dev/null
openssl verify -purpose sslserver -CAfile "$ca" -untrusted "$issuer" -verify_hostname "$cluster_name" "$certificate" >/dev/null
openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL client : Yes'
openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL server : Yes'
openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$api_name"
openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$cluster_name"

certificate_public_key=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | openssl dgst -sha256)
key_public_key=$(openssl pkey -in "$key" -pubout -outform DER | openssl dgst -sha256)
test "$certificate_public_key" = "$key_public_key"
