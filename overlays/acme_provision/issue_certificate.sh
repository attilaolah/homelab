#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
  echo "Usage: acme-provision-issue-certificate <acme-host>" >&2
  exit 2
fi

acme_host=$1

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  systemctl unset-environment ACME_PROVISION_HOST || true
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

systemctl set-environment "ACME_PROVISION_HOST=$acme_host"
systemctl start issue-tls-certificate.service || true
result="$(systemctl show -P Result issue-tls-certificate.service)"
[[ "$result" == success ]]
