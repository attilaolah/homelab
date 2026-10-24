{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  common = import ../tpm12/common.nix {
    inherit config lib pkgs;
    pki = import (inputs.self + /modules/lib/pki.nix);
  };
  template = import (inputs.self + /modules/lib/template.nix);
in {
  imports = [../tpm12/base.nix];

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "tpm-tls-bootstrap";
      runtimeInputs = with pkgs; [coreutils openssl simple-tpm-pk11];
      text = template ./tpm_tls_bootstrap.sh {
        inherit (common) commonName opensslConf;
        pkcs11OpenSslUri = common.pkcs11.openSslUri;
        simpleTpmPk11Conf = common.simpleTpmPk11Conf;
        tpmCaCsr = common.pki.tpm.ca.csr;
        tpmCaKey = common.pki.tpm.ca.key;
        tpmDirectory = common.tpm;
      };
    })
  ];
}
