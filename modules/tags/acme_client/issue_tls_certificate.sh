#!/usr/bin/env bash

set -euo pipefail

: "${ACME_HOSTS:?}"
: "${ACME_DOMAIN:?}"
: "${ACME_PORT:?}"
: "${ACME_ACCOUNT:?}"
: "${ACME_COMMON_NAME:?}"
: "${ACME_LAN_IP:?}"
: "${ACME_STATE:?}"
: "${ACME_TLS:?}"
: "${ACME_TLS_CERTIFICATE:?}"
: "${ACME_TLS_KEY:?}"
: "${DEPLOY_ACCOUNT:?}"

read -r -a acme_hosts <<<"${ACME_HOSTS}"
provision_host="${ACME_PROVISION_HOST:-}"
if [[ -n "${provision_host}" ]]; then
  found=0
  for acme_host in "${acme_hosts[@]}"; do
    if [[ "${acme_host}" == "${provision_host}" ]]; then
      found=1
      break
    fi
  done
  if [[ "${found}" -ne 1 ]]; then
    echo "Unknown ACME endpoint: ${provision_host}" >&2
    exit 1
  fi
  acme_hosts=("${provision_host}")
fi

prefix="${ACME_STATE}/certificates/${ACME_COMMON_NAME}"
cert="${prefix}.crt"
key="${prefix}.key"
success=0
for acme_host in "${acme_hosts[@]}"; do
  acme_fqdn="${acme_host}.${ACME_DOMAIN}"
  acme_url="https://${acme_fqdn}:${ACME_PORT}/acme/internal/directory"
  account_server="${acme_fqdn}_${ACME_PORT}"
  account_dir="${ACME_STATE}/accounts/${account_server}/${ACME_ACCOUNT}"
  account_json="${account_dir}/account.json"
  account_key="${account_dir}/${ACME_ACCOUNT}.key"
  bootstrap_eab="${ACME_STATE}/bootstrap-eab/${acme_host}"

  if [[ "${DEPLOY_ACCOUNT}" == 1 ]]; then
    account_json_variable="ACME_ACCOUNT_JSON_${acme_host}"
    account_key_variable="ACME_ACCOUNT_KEY_${acme_host}"
    secret_account_json="${!account_json_variable:-}"
    secret_account_key="${!account_key_variable:-}"
    if [[ -s "${secret_account_json}" && -s "${secret_account_key}" ]]; then
      install -d -m 0700 "${account_dir}"
      install -m 0600 "${secret_account_json}" "${account_json}"
      install -m 0600 "${secret_account_key}" "${account_key}"
    fi
  fi

  lego_common=(
    --accept-tos
    --email "${ACME_ACCOUNT}"
    --server "${acme_url}"
    --path "${ACME_STATE}"
    --domains "${ACME_COMMON_NAME}"
    --domains "${ACME_LAN_IP}"
    --key-type ec256
    --tls
    --tls.address :443
  )

  if [[ ! -s "${account_json}" || ! -s "${account_key}" ]]; then
    rm -f "${account_json}" "${account_key}"
    if [[ ! -s "${bootstrap_eab}/kid" || ! -s "${bootstrap_eab}/hmac-key" ]]; then
      echo "Skipping ACME endpoint ${acme_host}: no account state or bootstrap EAB credentials"
      continue
    fi

    lego_common+=(
      --eab
      --eab.kid "$(cat "${bootstrap_eab}/kid")"
      --eab.hmac "$(cat "${bootstrap_eab}/hmac-key")"
    )
  else
    # Lego refuses EAB-required directories unless EAB flags are present,
    # even when it already has account state and does not register.
    eab_placeholder="$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')"
    lego_common+=(
      --eab
      --eab.kid "${eab_placeholder}"
      --eab.hmac "${eab_placeholder}"
    )
  fi

  if [[ -e "${cert}" && -e "${key}" ]]; then
    if lego run "${lego_common[@]}" \
      --no-random-sleep \
      --renew-days 7 \
      --reuse-key; then
      success=1
      break
    fi
  elif lego run "${lego_common[@]}"; then
    success=1
    break
  fi
done

if [[ "${success}" -ne 1 ]]; then
  echo "Failed to issue or renew certificate from all ACME endpoints" >&2
  exit 1
fi

install -d -m 0750 -o root -g tls "${ACME_TLS}"
install -m 0640 -o root -g tls "${key}" "${ACME_TLS_KEY}.new"
install -m 0644 -o root -g tls "${cert}" "${ACME_TLS_CERTIFICATE}.new"
mv -f "${ACME_TLS_KEY}.new" "${ACME_TLS_KEY}"
mv -f "${ACME_TLS_CERTIFICATE}.new" "${ACME_TLS_CERTIFICATE}"
