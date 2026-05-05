{
  config,
  pkgs,
  ...
}: let
  b = "ca";
  crt = "${b}.crt";
  key = "${b}.key";
  tpm = "/var/lib/pki/tpm";
  files = config.clan.core.vars.generators.tpm.files;
in {
  clan.core.vars.generators = {
    tpm-owner-auth = {
      files.owner-auth = {
        secret = true;
        deploy = false;
      };
      runtimeInputs = with pkgs; [xkcdpass];
      script = ''
        xkcdpass --numwords 6 --delimiter - --count 1 | tr -d "\n" > "$out/owner-auth"
      '';
    };

    tpm = {
      files = {
        "${key}" = {
          secret = true;
          deploy = true;
        };
        "${crt}" = {
          secret = false;
          deploy = false;
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${tpm} 0700 root root - -"
    "L+ ${tpm}/${key} - - - - ${files.${key}.path}"
    "L+ ${tpm}/${crt} - - - - ${files.${crt}.path}"
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
