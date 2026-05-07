{
  clan-core,
  domain,
  machineData,
}: final: _prev: let
  inherit (final.stdenv.hostPlatform) system;

  acme = import ../modules/tags/tpm12/acme_common.nix;
  acmeFqdn = "0.acme.${domain}";
  acmeMachines = final.lib.escapeShellArgs machineData.tags.acme;
  acmePath = "/run/pki/acme";
in {
  acme-eab-add = final.writeShellApplication {
    name = "acme-eab-add";
    runtimeInputs = [
      clan-core.packages.${system}.clan-cli
      final.coreutils
      final.gnused
      final.jq
    ];
    text = ''
      set -euo pipefail

      if [[ $# -ne 1 ]]; then
        echo "usage: acme-eab-add <machine>" >&2
        exit 2
      fi

      machine=$1
      acme_machines=(${acmeMachines})
      acme_url=https://${acmeFqdn}:${toString acme.port}
      common_name="$machine.${domain}"
      account="root@$common_name"
      account_dir="${acmePath}/accounts/${acmeFqdn}_${toString acme.port}/$account"
      cert_dir="${acmePath}/certificates"
      account_secret_dir="/run/secrets/vars/acme-account"
      account_secret_backup="${acmePath}/previous-acme-account"
      bootstrap_eab="${acmePath}/bootstrap-eab"
      provisioned=0
      cleanup_bootstrap_eab() {
        clan ssh "$machine" -c sh -c "rm -f ''${bootstrap_eab}/kid ''${bootstrap_eab}/hmac-key; rmdir ''${bootstrap_eab} 2>/dev/null || true" || true
        if [[ "$provisioned" -eq 0 ]]; then
          clan ssh "$machine" -c sh -c "if [ ! -e '$account_secret_dir' ] && [ -e '$account_secret_backup' ]; then mv '$account_secret_backup' '$account_secret_dir'; fi" || true
        else
          clan ssh "$machine" -c sh -c "rm -rf '$account_secret_backup'" || true
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

      for acme_machine in "''${acme_machines[@]}"; do
        clan ssh "$acme_machine" -c systemctl stop step-ca-acme.service
        if ! clan ssh "$acme_machine" -c acme-eab-add \
          --db ${acme.stepPath}/db \
          --kid "$kid" \
          --hmac-key "$hmac_key" \
          --reference "$machine" \
          --replace; then
          clan ssh "$acme_machine" -c systemctl start step-ca-acme.service
          exit 1
        fi
        clan ssh "$acme_machine" -c systemctl start step-ca-acme.service
        clan ssh "$acme_machine" -c systemctl is-active --quiet step-ca-acme.service
      done

      clan ssh "$machine" -c systemctl stop issue-tls-certificate.service
      clan ssh "$machine" -c sh -c "rm -rf '$account_secret_backup'; if [ -e '$account_secret_dir' ]; then mv '$account_secret_dir' '$account_secret_backup'; fi"
      clan ssh "$machine" -c sh -c "rm -rf '$account_dir'; rm -f '$cert_dir/$common_name.crt' '$cert_dir/$common_name.issuer.crt' '$cert_dir/$common_name.json' '$cert_dir/$common_name.key'"
      clan ssh "$machine" -c sh -c "install -d -m 0700 ''${bootstrap_eab}"
      printf '%s' "$kid" |
        clan ssh "$machine" -c sh -c "umask 077; cat > ''${bootstrap_eab}/kid"
      printf '%s' "$hmac_key" |
        clan ssh "$machine" -c sh -c "umask 077; cat > ''${bootstrap_eab}/hmac-key"
      clan ssh "$machine" -c sh -c "systemctl start issue-tls-certificate.service || true; test \"\$(systemctl show -P Result issue-tls-certificate.service)\" = success"
      clan ssh "$machine" -c sh -c "test -s '$account_dir/account.json' -a -s '$account_dir/keys/$account.key'"

      # Base64 keeps SSH transport from changing line endings in JSON or PEM data.
      fetch_remote_file "$account_dir/account.json" |
        jq -c . |
        clan vars set "$machine" acme-account/account.json
      fetch_remote_file "$account_dir/keys/$account.key" |
        clan vars set "$machine" acme-account/account.key
      clan vars fix "$machine"
      provisioned=1

      printf 'ACME URL: %s/acme/internal/directory\n' "$acme_url"
      printf 'Stored ACME account for: %s\n' "$account"
    '';
  };
}
