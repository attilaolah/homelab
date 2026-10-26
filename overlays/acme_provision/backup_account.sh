#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: acme-provision-backup-account <json> <json-backup> <key> <key-backup>" >&2
  exit 2
fi

account_secret_json=$1
account_secret_json_backup=$2
account_secret_key=$3
account_secret_key_backup=$4

if [[ -e "$account_secret_json" ]]; then
  mv -f "$account_secret_json" "$account_secret_json_backup"
fi
if [[ -e "$account_secret_key" ]]; then
  mv -f "$account_secret_key" "$account_secret_key_backup"
fi
