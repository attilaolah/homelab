{
  config,
  lib,
  pkgs,
  ...
}: let
  common = import ./common.nix {inherit config lib pkgs;};
in {
  imports = [./base.nix];

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "tpm-tls-bootstrap";
      runtimeInputs = with pkgs; [coreutils openssl simple-tpm-pk11];
      text = ''
        set -euo pipefail

        key=${common.tpm}/ca.key
        csr=${common.tpm}/ca.csr

        if [[ -e "$key" ]]; then
          echo "$key already exists" >&2
          exit 1
        fi

        install -d -m 0700 ${common.tpm}
        stpm-keygen -o "$key"

        OPENSSL_CONF=${common.opensslConf} \
        SIMPLE_TPM_PK11_CONFIG=${common.simpleTpmPk11Conf} \
          openssl req \
            -new \
            -engine pkcs11 \
            -keyform engine \
            -key "${common.pkcs11.openSslUri}" \
            -subj "/CN=TLS CA: ${common.commonName}" \
            -out "$csr"

        echo "wrote $key"
        echo "wrote $csr"
      '';
    })
  ];
}
