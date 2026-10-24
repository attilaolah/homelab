{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (config.clan.core.vars.generators.tpm) files;
  common = import ./common.nix {
    inherit config lib pkgs;
    pki = import (inputs.self + /modules/lib/pki.nix);
  };
in {
  imports = [./base.nix];

  environment.systemPackages = [pkgs.tpm-tools];

  clan.core.vars.generators = {
    tpm = {
      files = {
        "${common.key}" = {
          secret = true;
          deploy = true;
        };
        "${common.crt}" = {
          secret = false;
          deploy = false;
        };
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "L+ ${common.tpm}/${common.key} - - - - ${files.${common.key}.path}"
      "L+ ${common.tpm}/${common.crt} - - - - ${files.${common.crt}.path}"
      "r ${common.pki.tpm.ca.csr}"
    ];

    services.issue-tls-certificate = let
      after = [
        "tcsd.service"
        "systemd-tmpfiles-setup.service"
      ];
    in {
      inherit after;
      description = "Issue short-lived TLS certificate from TPM CA";
      wantedBy = ["multi-user.target"];
      wants = after;
      path = with pkgs; [coreutils openssl];

      serviceConfig = {
        Type = "oneshot";
        Environment = "HOME=${common.tpm}";
        UMask = "0077";
        PrivateTmp = true;
      };

      environment = {
        OPENSSL_CONF = common.opensslConf;
        SIMPLE_TPM_PK11_CONFIG = common.simpleTpmPk11Conf;
        PKI_RUNTIME_DIRECTORY = common.pki.dir;
        TLS_CERTIFICATE = common.pki.tls.crt;
        TLS_CERTIFICATE_EXTENSIONS = common.certExt;
        TLS_CERTIFICATE_FILE = builtins.baseNameOf common.pki.tls.crt;
        TLS_DIRECTORY = common.tls;
        TLS_KEY = common.pki.tls.key;
        TLS_KEY_FILE = builtins.baseNameOf common.pki.tls.key;
        TLS_REQUEST_CONFIG = common.reqConf;
        TPM_CA_CERTIFICATE = common.pki.tpm.ca.crt;
        TPM_CA_KEY_URI = common.pkcs11.openSslUri;
      };

      script = builtins.readFile ./issue_tls_certificate.sh;
    };

    timers.issue-tls-certificate = {
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
}
