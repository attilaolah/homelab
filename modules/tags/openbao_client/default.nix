{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  common = import ../openbao_common.nix {inherit config inputs lib;};
  inherit (common) domain hostName tls;
  apiName = "${hostName}.node.${domain}";
  validateClientTls = pkgs.writeShellApplication {
    name = "openbao-validate-client-tls";
    runtimeInputs = with pkgs; [coreutils gnugrep openssl];
    text = ''
      set -euo pipefail

      ca=$1
      certificate=$2
      key=$3
      client_name=$4

      test -r "$ca"
      test -r "$certificate"
      test -r "$key"
      openssl verify -purpose sslclient -CAfile "$ca" -verify_hostname "$client_name" "$certificate" >/dev/null
      openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL client : Yes'
      openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$client_name"

      certificate_public_key=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | openssl dgst -sha256)
      key_public_key=$(openssl pkey -in "$key" -pubout -outform DER | openssl dgst -sha256)
      test "$certificate_public_key" = "$key_public_key"
    '';
  };
in
  lib.mkMerge [
    common.module

    {
      users.users.caddy.extraGroups = ["tls"];

      systemd.services.openbao-client-identity = {
        description = "Validate the ${hostName} OpenBao mTLS identity";
        after = ["issue-tls-certificate.service"];
        requires = ["issue-tls-certificate.service"];
        before = ["caddy.service"];
        requiredBy = ["caddy.service"];
        serviceConfig = {
          Type = "oneshot";
          User = "caddy";
          Group = "caddy";
          SupplementaryGroups = ["tls"];
          RemainAfterExit = true;
          UMask = "0077";
          ExecStart = "${lib.getExe validateClientTls} ${tls.ca} ${tls.certificate} ${tls.key} ${apiName}";
        };
      };
    }
  ]
