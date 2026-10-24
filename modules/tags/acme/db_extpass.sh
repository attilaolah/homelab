#!/usr/bin/env bash

set -euo pipefail

if [[ ! -s @dbKeySealed@ ]]; then
  echo "sealed DB key is missing (@dbKeySealed@)" >&2
  exit 1
fi

exec tpm_unsealdata -z -i @dbKeySealed@
