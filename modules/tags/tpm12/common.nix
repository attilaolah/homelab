{
  config,
  lib,
  pki,
  pkgs,
}: let
  pkcs11 = import ./pkcs11.nix {inherit lib pkgs;};

  crt = builtins.baseNameOf pki.tpm.ca.crt;
  key = builtins.baseNameOf pki.tpm.ca.key;
  tpm = pki.tpm.dir;

  commonName = "${config.networking.hostName}.node.${config.networking.domain}";
  subjectAltName = lib.concatStringsSep "," (
    (map (dnsName: "DNS:${dnsName}") [commonName])
    ++ ["IP:${config.homelab.lan.ip4}"]
  );
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
  simpleTpmPk11Conf = pkgs.replaceVars ./templates/simple-tpm-pk11.conf.in {
    caKey = "${tpm}/${key}";
  };
}
