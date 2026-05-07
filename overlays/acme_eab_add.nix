{
  clan-core,
  domain,
  machineData,
}: final: _prev: let
  inherit (final.stdenv.hostPlatform) system;

  acmeMachine = builtins.head machineData.tags.acme;
  acmeFqdn = "0.acme.${domain}";
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
      acme_machine=${acmeMachine}
      acme_url=https://${acmeFqdn}:9000
      password_file=/run/step-ca-admin-password

      cleanup() {
        clan ssh "$acme_machine" -c rm -f "$password_file"
      }
      trap cleanup EXIT

      clan vars get "$acme_machine" acme-admin/password |
        clan ssh "$acme_machine" -c install -m 0600 /dev/stdin "$password_file"

      clan ssh "$acme_machine" -c systemctl restart step-ca-acme.service
      clan ssh "$acme_machine" -c systemctl is-active --quiet step-ca-acme.service

      clan ssh "$acme_machine" -c \
        nix shell nixpkgs#step-cli -c step ca acme eab add internal "$machine" \
          --admin-subject step \
          --admin-provisioner "Admin JWK" \
          --admin-password-file "$password_file" \
          --ca-url "$acme_url" \
          --root /var/lib/pki/tpm/ca.crt
    '';
  };
}
