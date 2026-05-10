{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;

  acme = import ./acme_common.nix;
  machineData = import (inputs.self + /inventory/data.nix);
  common = import ./tpm12/common.nix {inherit config lib pkgs;};
  dbPath = "${acme.stepPath}/db";
  dbCryptPath = "${dbPath}.crypt";
  dbKeySealed = config.clan.core.vars.generators.acme-db.files."key.sealed".path;
  backendAddress = "127.0.0.1:${toString (acme.port + 1)}";
  dbExtpass = pkgs.writeShellApplication {
    name = "step-ca-db-extpass";
    runtimeInputs = with pkgs; [coreutils tpm-tools];
    text = ''
      set -euo pipefail

      if [[ ! -s ${dbKeySealed} ]]; then
        echo "sealed DB key is missing (${dbKeySealed})" >&2
        exit 1
      fi

      key="$(mktemp /run/step-ca-db-key.XXXXXX)"
      cleanup() {
        rm -f "$key"
      }
      trap cleanup EXIT

      tpm_unsealdata -z -i ${dbKeySealed} -o "$key"
      cat "$key"
    '';
  };

  acmeFqdns = map (name: "${name}.${config.networking.domain}") (builtins.attrNames config.homelab.acme.hosts);
  acmeClients = lib.unique ((machineData.tags.acme_client or []) ++ (machineData.tags.acme_client_bootstrap or []));
  acmeFirewallRules =
    ''
      iptables -I nixos-fw 1 -p tcp --dport ${toString acme.port} -j DROP
    ''
    + lib.concatMapStrings (machine: ''
      iptables -I nixos-fw 1 -p tcp --dport ${toString acme.port} -s ${machineData.machines.${machine}.ip} -j ACCEPT
    '')
    acmeClients;
  caConfig = (pkgs.formats.json {}).generate "step-ca.json" {
    root = config.clan.core.vars.generators.tls-ca.files."ca.crt".path;
    crt = "${common.tpm}/${common.crt}";
    key = common.pkcs11.key;
    address = backendAddress;
    dnsNames = acmeFqdns;
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
  };
in {
  clan.core.vars.generators.acme-db.files."key.sealed" = {
    secret = true;
    deploy = true;
  };

  networking.firewall.extraCommands = acmeFirewallRules;

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
        before = ["var-lib-step\\x2dca-db.mount"];
        path = with pkgs; [gocryptfs];
        unitConfig.StopWhenUnneeded = true;

        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };

        script = ''
          set -euo pipefail

          if [[ ! -s ${dbKeySealed} ]]; then
            echo "sealed DB key is missing (${dbKeySealed})" >&2
            exit 1
          fi

          if [[ ! -f ${dbCryptPath}/gocryptfs.conf ]]; then
            ${lib.getExe' pkgs.gocryptfs "gocryptfs"} -q -init -extpass ${lib.getExe dbExtpass} ${dbCryptPath}
          fi
        '';
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
        unitConfig.StopWhenUnneeded = true;

        environment = {
          HOME = common.tpm;
          SIMPLE_TPM_PK11_CONFIG = common.simpleTpmPk11Conf;
          STEPPATH = acme.stepPath;
        };

        serviceConfig = {
          Type = "simple";
          StateDirectory = "step-ca";
          StateDirectoryMode = "0700";
          RequiresMountsFor = [dbPath];
          ExecStart = "${lib.getExe pkgs.step-ca} ${caConfig}";
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
        path = with pkgs; [coreutils netcat-openbsd];

        serviceConfig = {
          Type = "notify";
          ExecStartPre = lib.getExe (pkgs.writeShellApplication {
            name = "wait-step-ca-backend";
            runtimeInputs = with pkgs; [coreutils netcat-openbsd];
            text = ''
              set -euo pipefail

              deadline=$((SECONDS + 30))
              while ! nc -z 127.0.0.1 ${toString (acme.port + 1)}; do
                if (( SECONDS >= deadline )); then
                  echo "step-ca backend did not become ready on ${backendAddress}" >&2
                  exit 1
                fi
                sleep 0.2
              done
            '';
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
        options = "extpass=${lib.getExe dbExtpass}";
        startLimitBurst = 3;
        unitConfig = {
          Requires = ["step-ca-db-prepare.service"];
          After = ["step-ca-db-prepare.service"];
          StopWhenUnneeded = true;
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

  environment.systemPackages = [inputs.acme-eab.packages.${system}.acme-eab];
}
