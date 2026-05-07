{
  config,
  lib,
  pkgs,
  ...
}: let
  common = import ./tpm12/common.nix {inherit config lib pkgs;};

  acmeFqdns = map (name: "${name}.${config.networking.domain}") (builtins.attrNames config.homelab.acme.hosts);
  acmePort = 9000;
  stepPath = "/var/lib/step-ca";
in {
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw 1 -p tcp --dport ${toString acmePort} -s 192.168.1.0/24 -j ACCEPT
    iptables -I nixos-fw 1 -p tcp --dport ${toString acmePort} -s 192.168.1.0/30 -j DROP
    iptables -I nixos-fw 1 -s 192.168.1.1 -j DROP
  '';

  systemd = {
    tmpfiles.rules = [
      "d ${stepPath} 0700 root root - -"
    ];

    services.step-ca-acme = {
      description = "Step CA ACME service";
      after = ["tcsd.service" "systemd-tmpfiles-setup.service"];
      wants = ["tcsd.service" "systemd-tmpfiles-setup.service"];
      wantedBy = ["multi-user.target"];
      path = with pkgs; [step-ca step-cli step-kms-plugin];

      environment = {
        HOME = common.tpm;
        SIMPLE_TPM_PK11_CONFIG = common.simpleTpmPk11Conf;
        STEPPATH = stepPath;
      };

      serviceConfig = {
        Type = "simple";
        StateDirectory = "step-ca";
        StateDirectoryMode = "0700";
        ExecStart = let
          caConfig = (pkgs.formats.json {}).generate "step-ca.json" {
            root = config.clan.core.vars.generators.tls-ca.files."ca.crt".path;
            crt = "${common.tpm}/${common.crt}";
            key = common.pkcs11.key;
            address = ":${toString acmePort}";
            dnsNames = acmeFqdns;
            logger.format = "text";
            db = {
              type = "badgerv2";
              dataSource = "${stepPath}/db";
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
        in "${lib.getExe pkgs.step-ca} ${caConfig}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
