{
  config,
  lib,
  pkgs,
}: let
  inherit (config.networking) domain hostName;

  b = "ca";
  crt = "${b}.crt";
  key = "${b}.key";
  tpm = "/var/lib/pki/tpm";
  tls = "/run/pki/tls";

  commonName = "${hostName}.${domain}";
  subjectAltName = lib.concatMapStringsSep "," (dnsName: "DNS:${dnsName}") [hostName commonName];
  pkcs11Uri =
    "pkcs11:"
    + lib.concatStringsSep ";"
    (lib.mapAttrsToList (name: value: "${name}=${builtins.replaceStrings [" "] ["%20"] value}") {
      id = "%31%31%31%31";
      manufacturer = "simple-tpm-pk11 manufacturer";
      model = "model";
      object = "simple-tpm-private-key";
      serial = "serial";
      token = "Simple-TPM-PK11 token";
      type = "private";
    });

  certExt = pkgs.replaceVars ./templates/cert.ext.in {
    inherit subjectAltName;
  };
  opensslConf = pkgs.replaceVars ./templates/openssl.cnf.in {
    pkcs11Engine = "${pkgs.libp11}/lib/engines/pkcs11.so";
    pkcs11Module = "${pkgs.simple-tpm-pk11}/lib/libsimple-tpm-pk11.so.0.0.0";
  };
  reqConf = pkgs.replaceVars ./templates/req.cnf.in {
    inherit commonName subjectAltName;
  };
  simpleTpmPk11Conf = pkgs.replaceVars ./templates/simple-tpm-pk11.conf.in {
    caKey = "${tpm}/${key}";
  };
in {
  inherit
    b
    certExt
    commonName
    crt
    key
    opensslConf
    pkcs11Uri
    reqConf
    simpleTpmPk11Conf
    subjectAltName
    tls
    tpm
    ;
}
