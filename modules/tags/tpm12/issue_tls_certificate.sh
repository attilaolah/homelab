#!/usr/bin/env bash

set -euo pipefail

work="$(mktemp -d "${PKI_RUNTIME_DIRECTORY}/tls-work.XXXXXX")"
trap 'rm -rf "$work"' EXIT

openssl genpkey \
  -algorithm EC \
  -pkeyopt ec_paramgen_curve:P-256 \
  -out "$work/${TLS_KEY_FILE}"

openssl req \
  -new \
  -key "$work/${TLS_KEY_FILE}" \
  -out "$work/tls.csr" \
  -config "${TLS_REQUEST_CONFIG}"

openssl x509 \
  -req \
  -engine pkcs11 \
  -in "$work/tls.csr" \
  -CA "${TPM_CA_CERTIFICATE}" \
  -CAkeyform engine \
  -CAkey "${TPM_CA_KEY_URI}" \
  -set_serial "0x$(openssl rand -hex 16)" \
  -out "$work/${TLS_CERTIFICATE_FILE}" \
  -days 8 \
  -sha256 \
  -extfile "${TLS_CERTIFICATE_EXTENSIONS}"

install -d -m 0750 -o root -g tls "${TLS_DIRECTORY}"
install -m 0640 -o root -g tls "$work/${TLS_KEY_FILE}" "${TLS_KEY}.new"
install -m 0644 -o root -g tls "$work/${TLS_CERTIFICATE_FILE}" "${TLS_CERTIFICATE}.new"
cat "${TPM_CA_CERTIFICATE}" >> "${TLS_CERTIFICATE}.new"
chown root:tls "${TLS_CERTIFICATE}.new"
chmod 0644 "${TLS_CERTIFICATE}.new"
mv -f "${TLS_KEY}.new" "${TLS_KEY}"
mv -f "${TLS_CERTIFICATE}.new" "${TLS_CERTIFICATE}"
