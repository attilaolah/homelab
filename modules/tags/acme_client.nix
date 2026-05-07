{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (config.clan.core.vars.generators.acme-eab) files;
  inherit (config.networking) domain hostName;

  acme = import ./tpm12/acme_common.nix;
  machineData = import (inputs.self + /inventory/data.nix);

  acmeUrl = "https://0.acme.${domain}:${toString acme.port}/acme/internal/directory";
  commonName = "${hostName}.${domain}";
  state = "/run/pki/acme";
  tls = "/run/pki/tls";
in {
  clan.core.vars.generators.acme-eab = {
    files = {
      kid = {
        secret = false;
        deploy = true;
      };
      hmac-key = {
        secret = true;
        deploy = true;
      };
    };
    script = ''
      touch "$out/kid" "$out/hmac-key"
    '';
  };

  networking.firewall.extraCommands =
    lib.concatMapStringsSep "\n" (machine: ''
      iptables -I nixos-fw 1 -p tcp --dport 443 -s ${machineData.machines.${machine}.ip} -j ACCEPT
    '')
    machineData.tags.acme;

  systemd = {
    tmpfiles.rules = [
      "d ${state} 0700 root root - -"
    ];

    services.issue-tls-certificate = {
      description = "Issue short-lived TLS certificate from ACME";
      after = ["network-online.target" "systemd-tmpfiles-setup.service"];
      wants = ["network-online.target" "systemd-tmpfiles-setup.service"];
      wantedBy = ["multi-user.target"];
      path = with pkgs; [coreutils lego];

      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        PrivateTmp = true;
      };

      script = ''
        set -euo pipefail

        cert="${state}/certificates/${commonName}.crt"
        key="${state}/certificates/${commonName}.key"

        lego_common=(
          --accept-tos
          --email "root@${commonName}"
          --server "${acmeUrl}"
          --path "${state}"
          --domains "${commonName}"
          --eab
          --kid "$(cat ${files.kid.path})"
          --hmac "$(cat ${files."hmac-key".path})"
          --key-type ec256
          --tls
          --tls.port :443
        )

        if [[ -e "$cert" && -e "$key" ]]; then
          lego "''${lego_common[@]}" renew \
            --days 7 \
            --reuse-key
        else
          lego "''${lego_common[@]}" run
        fi

        install -d -m 0750 -o root -g tls ${tls}
        install -m 0640 -o root -g tls "$key" ${tls}/tls.key.new
        install -m 0644 -o root -g tls "$cert" ${tls}/tls.crt.new
        mv -f ${tls}/tls.key.new ${tls}/tls.key
        mv -f ${tls}/tls.crt.new ${tls}/tls.crt
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
