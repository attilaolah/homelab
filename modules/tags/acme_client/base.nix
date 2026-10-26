{deployAccount}: {
  config,
  inputs,
  lib,
  pkgs,
  utils,
  ...
}: let
  inherit (config.networking) domain;

  pki = import (inputs.self + /modules/lib/pki.nix);
  machineData = import (inputs.self + /inventory/data.nix);

  acmeHosts = builtins.sort builtins.lessThan (builtins.attrNames config.homelab.acme.hosts);
  commonName = "${config.networking.hostName}.node.${domain}";
  state = pki.acme.dir;
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
        script =
          lib.concatMapStringsSep "\n" (acmeHost: ''
            touch "$out/${acmeHost}-account.json" "$out/${acmeHost}-account.key"
          '')
          acmeHosts;
      };
    })

    {
      networking.firewall.extraInputRules =
        lib.concatMapStringsSep "\n" (machine: ''
          ip saddr ${machineData.machines.${machine}.ip} tcp dport 443 accept
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

          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
            PrivateTmp = true;
            Environment =
              (import (inputs.self + /modules/lib/systemd.nix) {inherit lib utils;} {
                ACME_HOSTS = lib.concatStringsSep " " acmeHosts;
                ACME_DOMAIN = "acme.${domain}";
                ACME_PORT = (import ../acme/common.nix {inherit pki;}).port;
                ACME_ACCOUNT = "root@${commonName}";
                ACME_COMMON_NAME = commonName;
                ACME_LAN_IP = config.homelab.lan.ip4;
                ACME_STATE = state;
                ACME_TLS = pki.tls.dir;
                ACME_TLS_CERTIFICATE = pki.tls.crt;
                ACME_TLS_KEY = pki.tls.key;
                DEPLOY_ACCOUNT =
                  if deployAccount
                  then "1"
                  else "0";
              })
              ++ lib.optionals deployAccount (lib.flatten (map (acmeHost: [
                  "ACME_ACCOUNT_JSON_${acmeHost}=${config.clan.core.vars.generators.acme-accounts.files."${acmeHost}-account.json".path}"
                  "ACME_ACCOUNT_KEY_${acmeHost}=${config.clan.core.vars.generators.acme-accounts.files."${acmeHost}-account.key".path}"
                ])
                acmeHosts));
            ExecStart = "${pkgs.writeShellApplication {
              name = "issue-tls-certificate";
              runtimeInputs = with pkgs; [coreutils lego];
              text = builtins.readFile ./issue_tls_certificate.sh;
            }}/bin/issue-tls-certificate";
          };
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
