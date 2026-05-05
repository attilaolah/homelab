{
  config,
  pkgs,
  ...
}: let
  tpmCa = config.clan.core.vars.generators.tpm-ca.files;
in {
  clan.core.vars.generators = {
    tpm-owner-auth = {
      files."owner-auth" = {
        secret = true;
        deploy = false;
      };
      runtimeInputs = with pkgs; [xkcdpass];
      script = ''
        xkcdpass --numwords 6 --delimiter - --count 1 | tr -d "\n" > "$out/owner-auth"
      '';
    };

    tpm-ca = {
      files."ca.key" = {
        secret = true;
        deploy = true;
      };
      files."ca.crt" = {
        secret = false;
        deploy = false;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/pki/tpm 0700 root root - -"
    "L+ /var/lib/pki/tpm/ca.key - - - - ${tpmCa."ca.key".path}"
    "L+ /var/lib/pki/tpm/ca.crt - - - - ${tpmCa."ca.crt".path}"
  ];

  services = {
    tcsd.enable = true;

    # Trousers/tcsd runs as user/group tss and needs access to TPM device nodes.
    udev.extraRules = ''
      SUBSYSTEM=="tpm", KERNEL=="tpm[0-9]*", GROUP="tss", MODE="0660"
      SUBSYSTEM=="tpmrm", KERNEL=="tpmrm[0-9]*", GROUP="tss", MODE="0660"
    '';
  };
}
