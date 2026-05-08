{deployAccount}: {
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (config.networking) domain hostName;

  acme = import ../acme_common.nix;
  machineData = import (inputs.self + /inventory/data.nix);

  account = "root@${commonName}";
  acmeHost = builtins.head (builtins.sort builtins.lessThan (builtins.attrNames config.homelab.acme.hosts));
  acmeFqdn = "${acmeHost}.${domain}";
  accountServer = "${acmeFqdn}_${toString acme.port}";
  acmeUrl = "https://${acmeFqdn}:${toString acme.port}/acme/internal/directory";
  bootstrapEab = "${state}/bootstrap-eab";
  commonName = "${hostName}.${domain}";
  state = "/run/pki/acme";
  tls = "/run/pki/tls";
in {
  config = lib.mkMerge [
    (lib.mkIf deployAccount {
      clan.core.vars.generators.acme-account = {
        files = {
          "account.json" = {
            secret = true;
            deploy = true;
          };
          "account.key" = {
            secret = true;
            deploy = true;
          };
        };
        script = ''
          touch "$out/account.json" "$out/account.key"
        '';
      };
    })

    {
      networking.firewall.extraCommands =
        lib.concatMapStringsSep "\n" (machine: ''
          iptables -I nixos-fw 1 -p tcp --dport 443 -s ${machineData.machines.${machine}.ip} -j ACCEPT
        '')
        machineData.tags.acme;

      systemd = {
        tmpfiles.rules = [
          "d ${state} 0700 root root - -"
        ];

        services.issue-tls-certificate = let
          after = ["network-online.target" "systemd-tmpfiles-setup.service"];
        in {
          inherit after;
          description = "Issue short-lived TLS certificate from ACME";
          wants = after;
          wantedBy = lib.optional deployAccount "multi-user.target";
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
            account_dir="${state}/accounts/${accountServer}/${account}"
            account_json="$account_dir/account.json"
            account_key="$account_dir/keys/${account}.key"

            ${lib.optionalString deployAccount ''
              if [[ -s ${config.clan.core.vars.generators.acme-account.files."account.json".path} && -s ${config.clan.core.vars.generators.acme-account.files."account.key".path} ]]; then
                install -d -m 0700 "$account_dir/keys"
                install -m 0600 ${config.clan.core.vars.generators.acme-account.files."account.json".path} "$account_json"
                install -m 0600 ${config.clan.core.vars.generators.acme-account.files."account.key".path} "$account_key"
              fi
            ''}

            lego_common=(
              --accept-tos
              --email "${account}"
              --server "${acmeUrl}"
              --path "${state}"
              --domains "${commonName}"
              --key-type ec256
              --tls
              --tls.port :443
            )

            if [[ ! -e "$account_json" ]]; then
              if [[ ! -s ${bootstrapEab}/kid || ! -s ${bootstrapEab}/hmac-key ]]; then
                echo "missing ACME account state and bootstrap EAB credentials" >&2
                exit 1
              fi

              lego_common+=(
                --eab
                --kid "$(cat ${bootstrapEab}/kid)"
                --hmac "$(cat ${bootstrapEab}/hmac-key)"
              )
            else
              # Lego refuses EAB-required directories unless EAB flags are present,
              # even when it already has account state and does not register.
              lego_common+=(
                --eab
                --kid unused
                --hmac dW51c2Vk
              )
            fi

            if [[ -e "$cert" && -e "$key" ]]; then
              lego "''${lego_common[@]}" renew \
                --days 7 \
                --reuse-key \
                --no-random-sleep
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

        timers = lib.mkIf deployAccount {
          issue-tls-certificate = {
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
      };
    }
  ];
}
