#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: acme-provision <acme-host> <machine>" >&2
  exit 2
fi

acme_host=$1
machine=$2
acme_hosts=(@acmeHostsEscaped@)
acme_machine="$acme_host"
found=0
for host in "${acme_hosts[@]}"; do
  if [[ "$host" == "$acme_host" ]]; then
    found=1
    break
  fi
done
if [[ "$found" -ne 1 ]]; then
  echo "Unknown ACME host: $acme_host" >&2
  echo "Known ACME hosts: ${acme_hosts[*]}" >&2
  exit 2
fi
acme_fqdn="$acme_host.acme.@domain@"
acme_url="https://${acme_fqdn}:@acmePort@"
common_name="$machine.node.@domain@"
if [[ -n ${CLAN_DIR:-} ]]; then
  clan_dir=$CLAN_DIR
else
  clan_dir=$(git rev-parse --show-toplevel)
fi
account="root@$common_name"
account_dir="@acmeDirectory@/accounts/${acme_fqdn}_@acmePort@/$account"
cert_dir="@acmeDirectory@/certificates"
account_secret_parent="/run/secrets/vars/acme-accounts"
account_secret_json="$account_secret_parent/$acme_host-account.json"
account_secret_key="$account_secret_parent/$acme_host-account.key"
account_secret_json_backup="@acmeDirectory@/previous-acme-account-$acme_host-account.json"
account_secret_key_backup="@acmeDirectory@/previous-acme-account-$acme_host-account.key"
bootstrap_eab="@acmeDirectory@/bootstrap-eab/$acme_host"
provisioned=0
cleanup_bootstrap_eab() {
  clan ssh "$acme_machine" -c systemctl start step-ca-acme.service || true
  clan ssh "$machine" -c sh -c "rm -f ${bootstrap_eab}/kid ${bootstrap_eab}/hmac-key; rmdir ${bootstrap_eab} 2>/dev/null || true" || true
  if [[ "$provisioned" -eq 0 ]]; then
    clan ssh "$machine" -c bash -s -- \
      "$account_secret_parent" "$account_secret_json" "$account_secret_json_backup" <<'EOF' || true
@restoreAccount@
EOF
    clan ssh "$machine" -c bash -s -- \
      "$account_secret_parent" "$account_secret_key" "$account_secret_key_backup" <<'EOF' || true
@restoreAccount@
EOF
  else
    clan ssh "$machine" -c sh -c "rm -rf '$account_secret_json_backup' '$account_secret_key_backup'" || true
  fi
}
fetch_remote_file() {
  remote_path=$1
  clan ssh "$machine" -c sh -c "printf __CLAN_FILE_BEGIN__; base64 -w0 '$remote_path'; printf __CLAN_FILE_END__" |
    sed -n 's/.*__CLAN_FILE_BEGIN__//; s/__CLAN_FILE_END__.*//p' |
    base64 -d
}
trap cleanup_bootstrap_eab EXIT

kid=$(
  head -c 24 /dev/urandom |
    base64 |
    tr '+/' '-_' |
    tr -d '=\n'
)
hmac_key=$(
  head -c 32 /dev/urandom |
    base64 |
    tr '+/' '-_' |
    tr -d '=\n'
)

clan ssh "$machine" -c true

clan ssh "$acme_machine" -c systemctl stop step-ca-acme.service
if ! clan ssh "$acme_machine" -c acme-eab add \
  --db @stepPath@/db \
  --kid "$kid" \
  --key "$hmac_key" \
  --reference "$machine/$acme_host" \
  --replace; then
  clan ssh "$acme_machine" -c systemctl start step-ca-acme.service
  exit 1
fi
clan ssh "$acme_machine" -c systemctl start step-ca-acme.service
clan ssh "$acme_machine" -c systemctl is-active --quiet step-ca-acme.service

clan ssh "$machine" -c systemctl stop issue-tls-certificate.service
clan ssh "$machine" -c bash -s -- \
  "$account_secret_json" "$account_secret_json_backup" \
  "$account_secret_key" "$account_secret_key_backup" <<'EOF'
@backupAccount@
EOF
clan ssh "$machine" -c sh -c "rm -rf '$account_dir'; rm -f '$cert_dir/$common_name.crt' '$cert_dir/$common_name.issuer.crt' '$cert_dir/$common_name.json' '$cert_dir/$common_name.key'"
clan ssh "$machine" -c sh -c "install -d -m 0700 ${bootstrap_eab}"
printf '%s' "$kid" |
  clan ssh "$machine" -c sh -c "umask 077; cat > ${bootstrap_eab}/kid"
printf '%s' "$hmac_key" |
  clan ssh "$machine" -c sh -c "umask 077; cat > ${bootstrap_eab}/hmac-key"
clan ssh "$machine" -c bash -s -- "$acme_host" <<'EOF'
@issueCertificate@
EOF
clan ssh "$machine" -c bash -c "[[ -s '$account_dir/account.json' && -s '$account_dir/$account.key' ]]"

# Base64 keeps SSH transport from changing line endings in JSON or PEM data.
fetch_remote_file "$account_dir/account.json" |
  jq -c . |
  clan vars set "$machine" "acme-accounts/$acme_host-account.json"
fetch_remote_file "$account_dir/$account.key" |
  clan vars set "$machine" "acme-accounts/$acme_host-account.key"
all_accounts_present=1
for host in "${acme_hosts[@]}"; do
  for file in account.json account.key; do
    if [[ ! -f "$clan_dir/vars/per-machine/$machine/acme-accounts/$host-$file/secret" ]]; then
      all_accounts_present=0
      break
    fi
  done
done
if [[ "$all_accounts_present" -eq 1 ]]; then
  clan vars fix "$machine"
fi
provisioned=1

printf 'ACME URL: %s/acme/internal/directory\n' "$acme_url"
printf 'Stored ACME account for: %s (%s)\n' "$account" "$acme_host"
