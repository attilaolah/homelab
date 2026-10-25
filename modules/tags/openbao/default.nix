{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (common) inventory tls;
  inherit (config.networking) hostName domain;

  common = import ./common.nix {inherit config inputs lib;};
  template = import (inputs.self + /modules/lib/template.nix);

  nodes = {
    cluster = inventory.tags.openbao or [];
    client = inventory.tags.openbao_client or [];
  };

  host = fqdn hostName;
  ports = lib.mapAttrs (_: toString) {
    api = 8200;
    cluster = 8201;
  };
  addrs = lib.mapAttrs (_: https host) ports;

  # TODO: Move this somewhere!
  fqdn = node: "${node}.node.${domain}";
  https = host: port: "https://${host}:${port}";
in
  lib.mkMerge [
    common.module

    {
      # Recovery material is shared between the Raft servers, but is only
      # available to an operator through the vars store, never on a host.
      clan.core.vars.generators.openbao-init = {
        share = true;
        files = lib.genAttrs (["initial-root-token"] ++ (map (n: "unseal-share-${toString n}") (lib.range 1 5))) (_: {
          secret = true;
          deploy = false;
        });
      };
    }

    {
      environment.systemPackages = [
        pkgs.openbao
        (
          pkgs.writeShellApplication {
            name = "openbao-provision-cryptfs";
            runtimeInputs = with pkgs; [coreutils gnugrep jq openbao openssl];
            text = template ./provision_cryptfs.sh {
              inherit domain;
              inherit (addrs) api;
              inherit (tls) ca certificate key;

              approvedHosts = lib.concatMapStringsSep "|" lib.escapeShellArg nodes.client;
            };
          }
        )
      ];

      networking.firewall.extraInputRules = lib.mkAfter ''
        ip saddr { ${
          lib.concatStringsSep ", "
          (map (node: inventory.machines.${node}.ip) nodes.cluster)
        } } tcp dport { ${ports.api}, ${ports.cluster} } accept
        ip saddr { ${
          lib.concatStringsSep ", "
          (map (node: inventory.machines.${node}.ip) nodes.client)
        } } tcp dport ${ports.api} accept
      '';

      users = {
        groups.openbao = {};
        users.openbao = {
          isSystemUser = true;
          group = "openbao";
        };
      };

      systemd.services.openbao = {
        description = "OpenBao Raft server";
        after = ["network-online.target" "issue-tls-certificate.service"];
        requires = ["issue-tls-certificate.service"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          User = "openbao";
          Group = "openbao";
          SupplementaryGroups = ["tls"];
          StateDirectory = "openbao";
          StateDirectoryMode = "0700";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = ["/var/lib/openbao"];
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStartPre = "${lib.getExe (pkgs.writeShellApplication {
            name = "openbao-validate-tls";
            runtimeInputs = with pkgs; [coreutils gnugrep openssl];
            text = builtins.readFile ./validate_tls.sh;
          })} ${tls.ca} ${tls.issuer} ${tls.certificate} ${tls.key} ${host} ${host}";
          ExecStart = "${lib.getExe pkgs.openbao} server -config=${
            pkgs.writeText "openbao.hcl" (template ./templates/openbao.hcl.in {
              inherit hostName;
              inherit (addrs) api cluster;
              inherit (tls) ca certificate key;

              apiPort = ports.api;
              clusterPort = ports.cluster;
              ip = inventory.machines.${hostName}.ip;
              retryJoins = lib.concatMapStringsSep "\n" (node:
                template ./templates/retry_join.hcl.in (let
                  host = fqdn node;
                in {
                  inherit host;
                  inherit (tls) ca certificate key;
                  api = https host ports.api;
                })) (lib.filter (node: node != hostName) nodes.cluster);
            })
          }";
          ExecReload = "${lib.getExe' pkgs.coreutils "kill"} -HUP $MAINPID";
        };
      };

      systemd.services.issue-tls-certificate.postStart = lib.mkAfter ''
        if ${pkgs.systemd}/bin/systemctl is-active --quiet openbao.service; then
          ${pkgs.systemd}/bin/systemctl reload openbao.service
        fi
      '';
    }
  ]
