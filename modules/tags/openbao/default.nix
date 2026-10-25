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

  # TODO: These are the same; use "fqdn".
  apiName = "${hostName}.node.${domain}";
  clusterName = "${hostName}.node.${domain}";

  hostIp = inventory.machines.${hostName}.ip;
  retryJoins = lib.concatMapStringsSep "\n" (node: ''
    retry_join {
      leader_api_addr = "https://${node}.node.${domain}:8200"
      leader_tls_servername = "${node}.node.${domain}"
      leader_ca_cert_file = "${tls.ca}"
      leader_client_cert_file = "${tls.certificate}"
      leader_client_key_file = "${tls.key}"
    }
  '') (lib.filter (node: node != hostName) nodes.cluster);
in
  lib.mkMerge [
    common.module

    {
      # TODO: refactor
      # Recovery material is shared between the Raft servers, but is only
      # available to an operator through the vars store, never on a host.
      clan.core.vars.generators.openbao-init = {
        share = true;
        files = {
          initial-root-token = {
            secret = true;
            deploy = false;
          };
          unseal-share-1 = {
            secret = true;
            deploy = false;
          };
          unseal-share-2 = {
            secret = true;
            deploy = false;
          };
          unseal-share-3 = {
            secret = true;
            deploy = false;
          };
          unseal-share-4 = {
            secret = true;
            deploy = false;
          };
          unseal-share-5 = {
            secret = true;
            deploy = false;
          };
        };
      };
    }

    {
      environment.systemPackages = [pkgs.openbao];

      networking.firewall.extraInputRules = lib.mkAfter ''
        ip saddr { ${lib.concatStringsSep ", " (map (node: inventory.machines.${node}.ip) nodes.cluster)} } tcp dport { 8200, 8201 } accept
        ip saddr { ${lib.concatStringsSep ", " (map (node: inventory.machines.${node}.ip) nodes.client)} } tcp dport 8200 accept
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
          })} ${tls.ca} ${tls.issuer} ${tls.certificate} ${tls.key} ${apiName} ${clusterName}";
          ExecStart = "${lib.getExe pkgs.openbao} server -config=${
            pkgs.writeText "openbao.hcl" (template ./templates/openbao.hcl.in {
              inherit apiName clusterName hostIp hostName retryJoins;
              tlsCa = tls.ca;
              tlsCertificate = tls.certificate;
              tlsKey = tls.key;
            })
          }";
        };
      };
    }

    # This is intentionally only installed on iris and has no WantedBy. An
    # operator supplies a short-lived root token after init/unseal, then starts
    # it explicitly. It can safely be rerun for certificate rotation.
    (lib.mkIf (hostName == "iris") {
      systemd.services.openbao-provision = {
        description = "Provision OpenBao Caddy certificate-auth access";
        after = ["network-online.target" "openbao.service"];
        requires = ["openbao.service"];
        wants = ["network-online.target"];
        unitConfig.ConditionPathExists = "/run/openbao/bootstrap.env";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          UMask = "0077";
          EnvironmentFile = "/run/openbao/bootstrap.env";
          ExecStart = lib.getExe (pkgs.writeShellApplication {
            name = "openbao-bootstrap";
            runtimeInputs = with pkgs; [coreutils gnugrep jq openbao openssl];
            text = template ./bootstrap.sh {
              apiAddress = "https://${apiName}:8200";
              tlsCa = tls.ca;
              tlsCertificate = tls.certificate;
              tlsKey = tls.key;
              clientProvisioning = lib.concatMapStringsSep "\n\n" (node:
                template ./caddy_client_provision.sh {
                  inherit domain node;
                  tlsCa = tls.ca;
                })
              nodes.client;
            };
          });
        };
      };
    })
  ]
