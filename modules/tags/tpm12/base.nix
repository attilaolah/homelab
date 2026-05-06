{
  config,
  lib,
  pkgs,
  ...
}: let
  common = import ./common.nix {inherit config lib pkgs;};
in {
  clan.core.vars.generators.tpm-owner-auth = {
    files.owner-auth = {
      secret = true;
      deploy = false;
    };
    runtimeInputs = with pkgs; [coreutils xkcdpass];
    script = ''
      xkcdpass --numwords 6 --delimiter - --count 1 |
        tr -d "\n" > "$out/owner-auth"
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${common.tpm} 0700 root root - -"
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
