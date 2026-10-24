#!/usr/bin/env bash

set -euo pipefail

ca=$1
certificate=$2
key=$3
api_name=$4
cluster_name=$5

test -r "$ca"
test -r "$certificate"
test -r "$key"
openssl verify -purpose sslserver -CAfile "$ca" -verify_hostname "$api_name" "$certificate" >/dev/null
openssl verify -purpose sslserver -CAfile "$ca" -verify_hostname "$cluster_name" "$certificate" >/dev/null
openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL client : Yes'
openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL server : Yes'
openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$api_name"
openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$cluster_name"

certificate_public_key=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | openssl dgst -sha256)
key_public_key=$(openssl pkey -in "$key" -pubout -outform DER | openssl dgst -sha256)
test "$certificate_public_key" = "$key_public_key"
