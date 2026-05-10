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
  dbCryptPath = "${acme.stepPath}/db.crypt";
  dbKeySealed = config.clan.core.vars.generators.acme-db.files."key.sealed".path;

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
    address = ":${toString acme.port}";
    dnsNames = acmeFqdns;
    logger.format = "text";
    db = {
      type = "badgerv2";
      dataSource = "${acme.stepPath}/db";
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
  clan.core.vars.generators.acme-db = {
    files."key.sealed" = {
      secret = true;
      deploy = true;
    };
    script = ''
      printf 'placeholder\n' > "$out/key.sealed"
    '';
  };

  networking.firewall.extraCommands = acmeFirewallRules;

  systemd = {
    tmpfiles.rules = [
      "d ${acme.stepPath} 0700 root root - -"
      "d ${dbCryptPath} 0700 root root - -"
      "d ${dbPath} 0700 root root - -"
    ];

    services = {
      step-ca-db-mount = let
        after = [
          "tcsd.service"
          "systemd-tmpfiles-setup.service"
        ];
      in {
        inherit after;
        description = "Mount encrypted Step CA Badger DB";
        wants = after;
        wantedBy = ["multi-user.target"];
        before = ["step-ca-acme.service"];
        path = with pkgs; [coreutils findutils gocryptfs tpm-tools util-linux];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };

        script = ''
          set -euo pipefail

          if mountpoint -q ${dbPath}; then
            mounted_source="$(findmnt -n -T ${dbPath} -o SOURCE || true)"
            if [[ "$mounted_source" == "${dbCryptPath}" ]]; then
              exit 0
            fi
            echo "unexpected mount at ${dbPath}: $mounted_source" >&2
            exit 1
          fi

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
          chmod 0600 "$key"

          if [[ ! -f ${dbCryptPath}/gocryptfs.conf ]]; then
            gocryptfs -q -init -passfile "$key" ${dbCryptPath}
          fi

          gocryptfs -q -passfile "$key" ${dbCryptPath} ${dbPath}
        '';

        postStop = ''
          if mountpoint -q ${dbPath}; then
            umount ${dbPath}
          fi
        '';
      };

      step-ca-acme = let
        after = [
          "tcsd.service"
          "systemd-tmpfiles-setup.service"
          "step-ca-db-mount.service"
        ];
      in {
        inherit after;
        description = "Step CA ACME service";
        wants = after;
        requires = ["step-ca-db-mount.service"];
        wantedBy = ["multi-user.target"];
        path = with pkgs; [step-ca step-cli step-kms-plugin];

        environment = {
          HOME = common.tpm;
          SIMPLE_TPM_PK11_CONFIG = common.simpleTpmPk11Conf;
          STEPPATH = acme.stepPath;
        };

        serviceConfig = {
          Type = "simple";
          StateDirectory = "step-ca";
          StateDirectoryMode = "0700";
          ExecStart = "${lib.getExe pkgs.step-ca} ${caConfig}";
          Restart = "on-failure";
          RestartSec = "10s";
        };
      };
    };
  };

  environment.systemPackages = [inputs.acme-eab.packages.${system}.acme-eab];
}
