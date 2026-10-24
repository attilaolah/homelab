{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  common = import ../openbao/common.nix {inherit config inputs lib;};
  inherit (common) hostName tls;
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
          ExecStart = "${lib.getExe (pkgs.writeShellApplication {
            name = "openbao-validate-client-tls";
            runtimeInputs = with pkgs; [coreutils gnugrep openssl];
            text = builtins.readFile ./validate_client_tls.sh;
          })} ${tls.ca} ${tls.certificate} ${tls.key} ${hostName}.node.${common.domain}";
        };
      };
    }
  ]
