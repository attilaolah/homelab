{
  config,
  lib,
  pki,
  pkgs,
}: let
  inherit (builtins) baseNameOf;

  pkcs11 = import ./pkcs11.nix {inherit lib pkgs;};

  crt = baseNameOf pki.tpm.ca.crt;
  key = baseNameOf pki.tpm.ca.key;
  tpm = pki.tpm.dir;

  commonName = "${config.networking.hostName}.node.${config.networking.domain}";
  subjectAltName = lib.concatStringsSep "," [
    "DNS:${commonName}"
    "IP:${config.homelab.lan.ip4}"
  ];
in {
  inherit commonName crt key pkcs11 pki subjectAltName tpm;

  tls = pki.tls.dir;

  certExt = pkgs.replaceVars ./templates/cert.ext.in {
    inherit subjectAltName;
  };
  opensslConf = pkgs.replaceVars ./templates/openssl.cnf.in {
    pkcs11Engine = "${pkgs.libp11}/lib/engines/pkcs11.so";
    pkcs11Module = pkcs11.modulePath;
  };
  reqConf = pkgs.replaceVars ./templates/req.cnf.in {
    inherit commonName subjectAltName;
  };
  simpleTpmPk11Conf = pkgs.writeText "simple_tpm_pk11.conf" "key ${tpm}/${key}\n";
}
