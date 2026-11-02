{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (common) fqdn host hostName https nodes pki ports tls;

  common = import ../openbao/common.nix {inherit config inputs lib;};
  template = import (inputs.self + /modules/lib/template.nix);

  cryptfsPath = pki.cryptfs.dir;
  cryptfsCryptPath = "${cryptfsPath}.crypt";
  cryptfsExtpass = pkgs.writeShellApplication {
    name = "cryptfs-extpass";
    runtimeInputs = with pkgs; [coreutils curl jq];
    text = template ./cryptfs_extpass.sh {
      inherit hostName;
      inherit (tls) ca certificate key;

      apis = lib.concatMapStringsSep " " (node: lib.escapeShellArg (https (fqdn node) ports.api)) nodes.cluster;
    };
  };
in
  lib.mkMerge [
    common.module

    {
      users.groups.cryptfs = {};

      systemd = {
        tmpfiles.rules = [
          "d ${cryptfsCryptPath} 0750 root cryptfs - -"
          "d ${cryptfsPath} 0750 root cryptfs - -"
        ];

        services = {
          openbao-client-identity = {
            description = "Validate the ${hostName} OpenBao mTLS identity";
            after = ["issue-tls-certificate.service"];
            requires = ["issue-tls-certificate.service"];
            wantedBy = ["multi-user.target"];
            serviceConfig = {
              Type = "oneshot";
              DynamicUser = true;
              SupplementaryGroups = ["tls"];
              RemainAfterExit = true;
              UMask = "0077";
              ExecStart = "${lib.getExe (pkgs.writeShellApplication {
                name = "openbao-validate-client-tls";
                runtimeInputs = with pkgs; [coreutils gnugrep openssl];
                text = builtins.readFile ./validate_client_tls.sh;
              })} ${tls.ca} ${tls.issuer} ${tls.certificate} ${tls.key} ${host}";
            };
          };

          cryptfs-prepare = let
            after = [
              "network-online.target"
              "openbao-client-identity.service"
              "systemd-tmpfiles-setup.service"
            ];
            requires = [
              "openbao-client-identity.service"
              "systemd-tmpfiles-setup.service"
            ];
          in {
            inherit after requires;
            description = "Prepare encrypted filesystem";
            wants = ["network-online.target"];
            unitConfig.StopWhenUnneeded = true;

            serviceConfig = {
              Type = "oneshot";
              UMask = "0077";
              ExecStart = lib.getExe (pkgs.writeShellApplication {
                name = "cryptfs-prepare";
                runtimeInputs = with pkgs; [coreutils gocryptfs];
                text = template ./cryptfs_prepare.sh {
                  inherit cryptfsCryptPath;
                  cryptfsExtpass = lib.getExe cryptfsExtpass;
                };
              });
            };
          };
        };

        mounts = [
          {
            description = "Encrypted filesystem";
            what = cryptfsCryptPath;
            where = cryptfsPath;
            type = "fuse.gocryptfs";
            options = "nofail,allow_other,extpass=${lib.getExe cryptfsExtpass},nosyslog";
            startLimitBurst = 3;
            unitConfig = {
              Requires = [
                "openbao-client-identity.service"
                "cryptfs-prepare.service"
              ];
              Wants = ["network-online.target"];
              After = [
                "network-online.target"
                "openbao-client-identity.service"
                "cryptfs-prepare.service"
              ];
            };
          }
        ];

        automounts = [
          {
            description = "Automount for encrypted filesystem";
            where = cryptfsPath;
            wantedBy = ["multi-user.target"];
          }
        ];
      };

      system.fsPackages = [pkgs.gocryptfs];
    }
  ]
