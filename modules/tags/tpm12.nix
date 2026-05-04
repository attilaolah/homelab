{
  services.tcsd.enable = true;

  # trousers/tcsd runs as user/group tss and needs access to TPM device nodes.
  services.udev.extraRules = ''
    SUBSYSTEM=="tpm", KERNEL=="tpm[0-9]*", GROUP="tss", MODE="0660"
    SUBSYSTEM=="tpmrm", KERNEL=="tpmrm[0-9]*", GROUP="tss", MODE="0660"
  '';
}
