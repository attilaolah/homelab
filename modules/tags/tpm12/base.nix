{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: {
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
    # The TPM key remains root-only; members of tls need traversal only to
    # read the public intermediate used to validate their leaf certificate.
    "d ${(import (inputs.self + /modules/lib/pki.nix)).tpm.dir} 0710 root tls - -"
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
