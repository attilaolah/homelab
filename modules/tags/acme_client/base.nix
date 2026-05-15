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
  acmeHosts = builtins.sort builtins.lessThan (builtins.attrNames config.homelab.acme.hosts);

  account = "root@${commonName}";
  commonName = "${hostName}.${domain}";
  state = "/run/pki/acme";
  tls = "/run/pki/tls";
  cert = "${state}/certificates/${commonName}.crt";
  key = "${state}/certificates/${commonName}.key";
in {
  config = lib.mkMerge [
    (lib.mkIf deployAccount {
      clan.core.vars.generators.acme-accounts = {
        files =
          lib.listToAttrs
          (lib.flatten (map (acmeHost: [
              {
                name = "${acmeHost}-account.json";
                value = {
                  secret = true;
                  deploy = true;
                };
              }
              {
                name = "${acmeHost}-account.key";
                value = {
                  secret = true;
                  deploy = true;
                };
              }
            ])
            acmeHosts));
        script = ''
          ${lib.concatMapStringsSep "\n" (acmeHost: ''
              touch "$out/${acmeHost}-account.json" "$out/${acmeHost}-account.key"
            '')
            acmeHosts}
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
          after = [
            "network-online.target"
            "systemd-tmpfiles-setup.service"
          ];
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

            acme_hosts=(${lib.escapeShellArgs acmeHosts})
            provision_host=''${ACME_PROVISION_HOST:-}
            if [[ -n "$provision_host" ]]; then
              found=0
              for acme_host in "''${acme_hosts[@]}"; do
                if [[ "$acme_host" == "$provision_host" ]]; then
                  found=1
                  break
                fi
              done
              if [[ "$found" -ne 1 ]]; then
                echo "unknown ACME endpoint: $provision_host" >&2
                exit 1
              fi
              acme_hosts=("$provision_host")
            fi

            success=0
            for acme_host in "''${acme_hosts[@]}"; do
              acme_fqdn="$acme_host.${domain}"
              acme_url="https://$acme_fqdn:${toString acme.port}/acme/internal/directory"
              account_server="''${acme_fqdn}_${toString acme.port}"
              account_dir="${state}/accounts/$account_server/${account}"
              account_json="$account_dir/account.json"
              account_key="$account_dir/keys/${account}.key"
              bootstrap_eab="${state}/bootstrap-eab/$acme_host"

              ${lib.optionalString deployAccount ''
                case "$acme_host" in
                ${lib.concatMapStringsSep "\n" (acmeHost: ''
                    ${acmeHost})
                      secret_account_json=${config.clan.core.vars.generators.acme-accounts.files."${acmeHost}-account.json".path}
                      secret_account_key=${config.clan.core.vars.generators.acme-accounts.files."${acmeHost}-account.key".path}
                      ;;
                  '')
                  acmeHosts}
                  *)
                    echo "unknown ACME endpoint: $acme_host" >&2
                    continue
                    ;;
                esac

                if [[ -s "$secret_account_json" && -s "$secret_account_key" ]]; then
                  install -d -m 0700 "$account_dir/keys"
                  install -m 0600 "$secret_account_json" "$account_json"
                  install -m 0600 "$secret_account_key" "$account_key"
                fi
              ''}

              lego_common=(
                --accept-tos
                --email "${account}"
                --server "$acme_url"
                --path "${state}"
                --domains "${commonName}"
                --key-type ec256
                --tls
                --tls.port :443
              )

              if [[ ! -s "$account_json" || ! -s "$account_key" ]]; then
                rm -f "$account_json" "$account_key"
                if [[ ! -s "$bootstrap_eab/kid" || ! -s "$bootstrap_eab/hmac-key" ]]; then
                  echo "skipping ACME endpoint $acme_host: no account state or bootstrap EAB credentials"
                  continue
                fi

                lego_common+=(
                  --eab
                  --kid "$(cat "$bootstrap_eab/kid")"
                  --hmac "$(cat "$bootstrap_eab/hmac-key")"
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

              if [[ -e "${cert}" && -e "${key}" ]]; then
                if lego "''${lego_common[@]}" renew \
                  --days 7 \
                  --reuse-key \
                  --no-random-sleep; then
                  success=1
                  break
                fi
              else
                if lego "''${lego_common[@]}" run; then
                  success=1
                  break
                fi
              fi
            done

            if [[ "$success" -ne 1 ]]; then
              echo "failed to issue or renew certificate from all ACME endpoints" >&2
              exit 1
            fi

            install -d -m 0750 -o root -g tls ${tls}
            install -m 0640 -o root -g tls "${key}" ${tls}/tls.key.new
            install -m 0644 -o root -g tls "${cert}" ${tls}/tls.crt.new
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
