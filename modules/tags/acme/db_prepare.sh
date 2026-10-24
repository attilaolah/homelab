#!/usr/bin/env bash

set -euo pipefail

if [[ ! -s @dbKeySealed@ ]]; then
  echo "sealed DB key is missing (@dbKeySealed@)" >&2
  exit 1
fi

if [[ ! -f @dbCryptPath@/gocryptfs.conf ]]; then
  gocryptfs -q -init -extpass @dbExtpass@ @dbCryptPath@
fi
