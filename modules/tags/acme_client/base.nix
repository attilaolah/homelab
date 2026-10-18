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
  commonName = "${hostName}.node.${domain}";

  pki = dir: "/run/pki/${dir}";
  tls = pki "tls";
  state = pki "acme";

  issueTlsCertificate = pkgs.writeShellApplication {
    name = "issue-tls-certificate";
    runtimeInputs = with pkgs; [coreutils lego];
    text = builtins.readFile ./issue_tls_certificate.sh;
  };
  serviceEnvironment =
    import (inputs.self + /modules/lib/systemd.nix) {inherit lib;} {
      acme_hosts = lib.concatStringsSep " " acmeHosts;
      acme_domain = domain;
      acme_port = acme.port;
      acme_account = account;
      acme_common_name = commonName;
      acme_lan_ip = config.homelab.lan.ip4;
      acme_state = state;
      acme_tls = tls;
      deploy_account =
        if deployAccount
        then "1"
        else "0";
    }
    ++ lib.optionals deployAccount (lib.flatten (map (acmeHost: [
        "ACME_ACCOUNT_JSON_${acmeHost}=${config.clan.core.vars.generators.acme-accounts.files."${acmeHost}-account.json".path}"
        "ACME_ACCOUNT_KEY_${acmeHost}=${config.clan.core.vars.generators.acme-accounts.files."${acmeHost}-account.key".path}"
      ])
      acmeHosts));
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

          serviceConfig = {
            Type = "oneshot";
            UMask = "0077";
            PrivateTmp = true;
            Environment = serviceEnvironment;
            ExecStart = "${issueTlsCertificate}/bin/issue-tls-certificate";
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
