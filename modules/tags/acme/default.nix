{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  acme = import ./common.nix {inherit pki;};
  common = import ../tpm12/common.nix {inherit config lib pkgs pki;};
  machineData = import (inputs.self + /inventory/data.nix);
  pki = import (inputs.self + /modules/lib/pki.nix);
  template = import (inputs.self + /modules/lib/template.nix);

  dbPath = "${acme.stepPath}/db";
  dbCryptPath = "${dbPath}.crypt";
  dbKeySealed = config.clan.core.vars.generators.acme-db.files."key.sealed".path;
  backendAddress = "127.0.0.1:${toString (acme.port + 1)}";
  dbExtpass = pkgs.writeShellApplication {
    name = "step-ca-db-extpass";
    runtimeInputs = with pkgs; [coreutils tpm-tools];
    text = template ./db_extpass.sh {inherit dbKeySealed;};
  };
in {
  clan.core.vars.generators.acme-db.files."key.sealed" = {
    secret = true;
    deploy = true;
  };

  networking.firewall.extraInputRules =
    lib.concatMapStrings (machine: ''
      ip saddr ${machineData.machines.${machine}.ip} tcp dport ${toString acme.port} accept
    '')
    (lib.unique ((machineData.tags.acme_client or []) ++ (machineData.tags."acme_client_bootstrap" or [])))
    + ''
      tcp dport ${toString acme.port} drop
    '';

  systemd = {
    tmpfiles.rules = [
      "d ${acme.stepPath} 0700 root root - -"
      "d ${dbCryptPath} 0700 root root - -"
      "d ${dbPath} 0700 root root - -"
    ];

    services = {
      step-ca-db-prepare = let
        after = [
          "tcsd.service"
          "systemd-tmpfiles-setup.service"
        ];
      in {
        inherit after;
        description = "Prepare encrypted Step CA Badger DB";
        wants = after;
        unitConfig.StopWhenUnneeded = true;

        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
          ExecStart = lib.getExe (pkgs.writeShellApplication {
            name = "step-ca-db-prepare";
            runtimeInputs = with pkgs; [coreutils gocryptfs];
            text = template ./db_prepare.sh {
              inherit dbKeySealed dbCryptPath;
              dbExtpass = lib.getExe dbExtpass;
            };
          });
        };
      };

      step-ca-acme = let
        after = [
          "tcsd.service"
          "systemd-tmpfiles-setup.service"
        ];
      in {
        inherit after;
        description = "Step CA ACME service";
        wants = after;
        path = with pkgs; [step-ca step-cli step-kms-plugin];
        unitConfig = {
          StopWhenUnneeded = true;
          RequiresMountsFor = [dbPath];
        };

        environment = {
          HOME = common.tpm;
          SIMPLE_TPM_PK11_CONFIG = common.simpleTpmPk11Conf;
          STEPPATH = acme.stepPath;
        };

        serviceConfig = {
          Type = "simple";
          StateDirectory = "step-ca";
          StateDirectoryMode = "0700";
          ExecStart = "${lib.getExe pkgs.step-ca} ${
            (pkgs.formats.json {}).generate "step-ca.json" {
              root = config.clan.core.vars.generators.${pki.cluster.ca.gen}.files.${pki.cluster.ca.crt}.path;
              crt = "${common.tpm}/${common.crt}";
              key = common.pkcs11.key;
              address = backendAddress;
              dnsNames = map (name: "${name}.acme.${config.networking.domain}") (builtins.attrNames config.homelab.acme.hosts);
              logger.format = "text";
              db = {
                type = "badgerv2";
                dataSource = "${dbPath}";
              };
              authority.provisioners = [
                {
                  type = "ACME";
                  name = "internal";
                  forceCN = true;
                  requireEAB = true;
                  claims = {
                    defaultTLSCertDuration = "192h";
                    maxTLSCertDuration = "192h";
                  };
                }
              ];
              kms = {
                type = "pkcs11";
                uri = common.pkcs11.kms;
              };
            }
          }";
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };

      step-ca-proxy = let
        after = [
          "step-ca-acme.service"
          "step-ca-proxy.socket"
        ];
      in {
        inherit after;
        description = "Socket-activated proxy to Step CA ACME backend";
        wants = after;
        requires = after;

        serviceConfig = {
          Type = "notify";
          ExecStartPre = lib.getExe (pkgs.writeShellApplication {
            name = "wait-step-ca-backend";
            runtimeInputs = with pkgs; [coreutils netcat-openbsd];
            text = template ./wait_backend.sh {
              inherit backendAddress;
              backendPort = toString (acme.port + 1);
            };
          });
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=2min ${backendAddress}";
        };
      };
    };

    mounts = [
      {
        description = "Encrypted Step CA Badger DB";
        what = dbCryptPath;
        where = dbPath;
        type = "fuse.gocryptfs";
        options = "extpass=${lib.getExe dbExtpass},nosyslog";
        startLimitBurst = 3;
        unitConfig = {
          Requires = ["step-ca-db-prepare.service"];
          After = ["step-ca-db-prepare.service"];
        };
      }
    ];

    automounts = [
      {
        description = "Automount for encrypted Step CA Badger DB";
        where = dbPath;
        wantedBy = ["multi-user.target"];
        automountConfig.TimeoutIdleSec = "10min";
      }
    ];

    sockets.step-ca-proxy = {
      description = "Socket activation for Step CA ACME endpoint";
      wantedBy = ["sockets.target"];
      listenStreams = [(toString acme.port)];
      socketConfig.Accept = false;
    };
  };

  system.fsPackages = [pkgs.gocryptfs];

  environment.systemPackages = [inputs.acme-eab.packages.${pkgs.stdenv.hostPlatform.system}.acme-eab];
}
