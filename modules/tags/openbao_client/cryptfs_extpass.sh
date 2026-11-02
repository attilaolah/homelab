#!/usr/bin/env bash

set -euo pipefail

ca="@ca@"
certificate="@certificate@"
key="@key@"
host="@hostName@"
role="cryptfs-$host"
secret_path="cryptfs/data/$host/key"
apis=(@apis@)

for file in "$ca" "$certificate" "$key"; do
  if [[ ! -r "$file" ]]; then
    echo "Required TLS file is not readable: $file" >&2
    exit 1
  fi
done

response_file=$(mktemp -p /run cryptfs-response.XXXXXX)
curl_error_file=
cleanup() {
  rm -f -- "$response_file" "${curl_error_file:-}"
}
trap cleanup EXIT
curl_error_file=$(mktemp -p /run cryptfs-error.XXXXXX)
chmod 600 "$response_file" "$curl_error_file"

login_payload=$(jq -cn --arg name "$role" '{name: $name}')
cryptfs_key=

for api in "${apis[@]}"; do
  if ! http_status=$(curl \
    --silent \
    --show-error \
    --connect-timeout 5 \
    --max-time 15 \
    --request POST \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --cacert "$ca" \
    --cert "$certificate" \
    --key "$key" \
    --header 'Content-Type: application/json' \
    --data "$login_payload" \
    "$api/v1/auth/cert/login" 2>"$curl_error_file"); then
    echo "Failed OpenBao cert login via $api" >&2
    cat "$curl_error_file" >&2
    continue
  fi

  if [[ $http_status != 200 ]]; then
    echo "Unexpected HTTP status $http_status during OpenBao cert login via $api" >&2
    cat "$curl_error_file" >&2
    cat "$response_file" >&2
    continue
  fi

  if ! token=$(jq -er '.auth.client_token | select(type == "string" and length > 0)' "$response_file" 2>/dev/null); then
    echo "Missing client token in OpenBao login response from $api" >&2
    continue
  fi

  read_ok=true
  if ! http_status=$(curl \
    --silent \
    --show-error \
    --connect-timeout 5 \
    --max-time 15 \
    --request GET \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --cacert "$ca" \
    --cert "$certificate" \
    --key "$key" \
    --header @- \
    "$api/v1/$secret_path" <<<"X-Vault-Token: $token" 2>"$curl_error_file"); then
    echo "Failed to read '$secret_path' from $api" >&2
    cat "$curl_error_file" >&2
    read_ok=false
  fi

  curl \
    --silent \
    --connect-timeout 5 \
    --max-time 10 \
    --request POST \
    --output /dev/null \
    --cacert "$ca" \
    --cert "$certificate" \
    --key "$key" \
    --header @- \
    "$api/v1/auth/token/revoke-self" <<<"X-Vault-Token: $token" 2>/dev/null || true

  if [[ $read_ok != true ]]; then
    continue
  fi

  if [[ $http_status != 200 ]]; then
    echo "Unexpected HTTP status $http_status while reading '$secret_path' from $api" >&2
    cat "$curl_error_file" >&2
    cat "$response_file" >&2
    continue
  fi

  if ! candidate_key=$(jq -er '.data.data.key | select(type == "string") | sub("[\r\n]+$"; "") | select(length > 0)' "$response_file" 2>/dev/null); then
    echo "Missing or empty 'key' field in '$secret_path' response from $api" >&2
    continue
  fi

  if [[ $candidate_key == *$'\n'* || $candidate_key == *$'\r'* ]]; then
    echo "Refusing multiline 'cryptfs' key from $api" >&2
    continue
  fi

  cryptfs_key=$candidate_key
  break
done

if [[ -z $cryptfs_key ]]; then
  echo "Failed to retrieve '$secret_path' from any OpenBao server" >&2
  exit 1
fi

printf '%s\n' "$cryptfs_key"
