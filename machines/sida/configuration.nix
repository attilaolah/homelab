{
  # Broadcom B43 Wi-Fi firmware is intentionally omitted because the Wi-Fi antenna is disconnected.
  imports = [ ../../modules/firmware_minimal.nix ];
  firmwareFile = ./firmware.txt;
}
