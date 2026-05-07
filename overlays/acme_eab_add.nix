{
  clan-core,
  domain,
  machineData,
}: final: _prev: let
  inherit (final.stdenv.hostPlatform) system;

  acme = import ../modules/tags/tpm12/acme_common.nix;
  acmeFqdn = "0.acme.${domain}";
  acmeMachines = final.lib.escapeShellArgs machineData.tags.acme;
in {
  acme-eab-add = final.writeShellApplication {
    name = "acme-eab-add";
    runtimeInputs = [
      clan-core.packages.${system}.clan-cli
      final.coreutils
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

      for acme_machine in "''${acme_machines[@]}"; do
        clan ssh "$acme_machine" -c systemctl stop step-ca-acme.service
        if ! clan ssh "$acme_machine" -c acme-eab-write \
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

      printf '%s' "$kid" |
        clan vars set "$machine" acme-eab/kid
      printf '%s' "$hmac_key" |
        clan vars set "$machine" acme-eab/hmac-key
      clan vars fix "$machine"

      printf 'ACME URL: %s/acme/internal/directory\n' "$acme_url"
      printf 'EAB KID: %s\n' "$kid"
      printf 'EAB HMAC key: %s\n' "$hmac_key"
    '';
  };
}
