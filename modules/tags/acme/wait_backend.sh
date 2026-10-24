#!/usr/bin/env bash

set -euo pipefail

deadline=$((SECONDS + 30))
while ! nc -z 127.0.0.1 @backendPort@; do
  if (( SECONDS >= deadline )); then
    echo "step-ca backend did not become ready on @backendAddress@" >&2
    exit 1
  fi
  sleep 0.2
done
