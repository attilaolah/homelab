#!/usr/bin/env bash

set -euo pipefail

: "${out:?}"

step certificate create "TLS CA: @domain@" "$out/@certificateFile@" "$out/@keyFile@" \
  --profile root-ca \
  --kty EC \
  --curve P-256 \
  --no-password \
  --insecure
