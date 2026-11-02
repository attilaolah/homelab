#!/usr/bin/env bash

set -euo pipefail

if [[ ! -f @cryptfsCryptPath@/gocryptfs.conf ]]; then
  gocryptfs -q -init -extpass @cryptfsExtpass@ @cryptfsCryptPath@
fi
