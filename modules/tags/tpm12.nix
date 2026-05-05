{pkgs, ...}: {
  clan.core.vars.generators.tpm-owner-auth = {
    files."owner-auth" = {
      secret = true;
      deploy = false;
    };
    runtimeInputs = with pkgs; [xkcdpass];
    script = ''
      xkcdpass --numwords 6 --delimiter - --count 1 | tr -d "\n" > "$out/owner-auth"
    '';
  };

  clan.core.vars.generators.tpm-ca = {
    files."ca.key" = {
      secret = true;
      deploy = false;
    };
    files."ca.crt" = {
      secret = false;
      deploy = false;
    };
  };

  services.tcsd.enable = true;

  # Trousers/tcsd runs as user/group tss and needs access to TPM device nodes.
  services.udev.extraRules = ''
    SUBSYSTEM=="tpm", KERNEL=="tpm[0-9]*", GROUP="tss", MODE="0660"
    SUBSYSTEM=="tpmrm", KERNEL=="tpmrm[0-9]*", GROUP="tss", MODE="0660"
  '';
}
