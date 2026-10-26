#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: acme-provision-restore-account <secret-parent> <secret> <backup>" >&2
  exit 2
fi

account_secret_parent=$1
account_secret=$2
account_secret_backup=$3

if [[ ! -e "$account_secret" && -e "$account_secret_backup" ]]; then
  install -d -m 0700 "$account_secret_parent"
  mv "$account_secret_backup" "$account_secret"
fi
