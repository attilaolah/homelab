{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.clan.core.vars.generators.tpm) files;
  common = import ./common.nix {inherit config lib pkgs;};
in {
  imports = [./base.nix];

  clan.core.vars.generators = {
    tpm = {
      files = {
        "${common.key}" = {
          secret = true;
          deploy = true;
        };
        "${common.crt}" = {
          secret = false;
          deploy = false;
        };
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "L+ ${common.tpm}/${common.key} - - - - ${files.${common.key}.path}"
      "L+ ${common.tpm}/${common.crt} - - - - ${files.${common.crt}.path}"
    ];

    services.issue-tls-certificate = let
      after = ["tcsd.service" "systemd-tmpfiles-setup.service"];
    in {
      inherit after;
      description = "Issue short-lived TLS certificate from TPM CA";
      wantedBy = ["multi-user.target"];
      wants = after;
      path = with pkgs; [coreutils openssl];

      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        PrivateTmp = true;
      };

      script = ''
        set -euo pipefail

        work="$(mktemp -d /run/pki/tls-work.XXXXXX)"
        trap 'rm -rf "$work"' EXIT

        openssl genpkey \
          -algorithm EC \
          -pkeyopt ec_paramgen_curve:P-256 \
          -out "$work/tls.key"

        openssl req \
          -new \
          -key "$work/tls.key" \
          -out "$work/tls.csr" \
          -config ${common.reqConf}

        OPENSSL_CONF=${common.opensslConf} \
        SIMPLE_TPM_PK11_CONFIG=${common.simpleTpmPk11Conf} \
          openssl x509 \
            -req \
            -engine pkcs11 \
            -in "$work/tls.csr" \
            -CA ${common.tpm}/${common.crt} \
            -CAkeyform engine \
            -CAkey "${common.pkcs11Uri}" \
            -set_serial "0x$(openssl rand -hex 16)" \
            -out "$work/tls.crt" \
            -days 8 \
            -sha256 \
            -extfile ${common.certExt}

        install -d -m 0750 -o root -g tls ${common.tls}
        install -m 0640 -o root -g tls "$work/tls.key" ${common.tls}/tls.key.new
        install -m 0644 -o root -g tls "$work/tls.crt" ${common.tls}/tls.crt.new
        cat ${common.tpm}/${common.crt} >> ${common.tls}/tls.crt.new
        chown root:tls ${common.tls}/tls.crt.new
        chmod 0644 ${common.tls}/tls.crt.new
        mv -f ${common.tls}/tls.key.new ${common.tls}/tls.key
        mv -f ${common.tls}/tls.crt.new ${common.tls}/tls.crt
      '';
    };

    timers.issue-tls-certificate = {
      description = "Refresh short-lived TLS certificate";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "2d";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
  };
}
