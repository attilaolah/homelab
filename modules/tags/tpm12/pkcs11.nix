{
  lib,
  pkgs,
}: let
  uri = attrs:
    "pkcs11:"
    + lib.concatStringsSep ";"
    (lib.mapAttrsToList (name: value: "${name}=${builtins.replaceStrings [" "] ["%20"] value}") attrs);

  idBytes = map toString [31 31 31 31];
  id = lib.concatStrings idBytes;
  uriId = lib.concatMapStrings (char: "%${char}") idBytes;
  modulePath = "${pkgs.simple-tpm-pk11}/lib/libsimple-tpm-pk11.so.0.0.0";
  object = "simple-tpm-private-key";
  token = "Simple-TPM-PK11 token";
in {
  inherit id idBytes modulePath object token uri uriId;

  openSslUri = uri {
    inherit object token;
    id = uriId;
    manufacturer = "simple-tpm-pk11 manufacturer";
    model = "model";
    serial = "serial";
    type = "private";
  };
  kms = uri {
    inherit token;
    module-path = modulePath;
  };
  key = uri {
    inherit object;
    id = uriId;
  };
}
