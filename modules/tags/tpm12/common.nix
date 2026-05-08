{
  config,
  lib,
  pkgs,
}: let
  inherit (config.networking) domain hostName;

  pkcs11 = import ./pkcs11.nix {inherit lib pkgs;};

  b = "ca";
  crt = "${b}.crt";
  key = "${b}.key";
  tpm = "/var/lib/pki/tpm";

  commonName = "${hostName}.${domain}";
  subjectAltName = lib.concatStringsSep "," (
    (map (dnsName: "DNS:${dnsName}") [hostName commonName])
    ++ ["IP:${config.homelab.lan.ip4}"]
  );
in {
  inherit b commonName crt key pkcs11 subjectAltName tpm;

  tls = "/run/pki/tls";

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
