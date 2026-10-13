{pkgs, ...}: {
  imports = [];

  hardware = {
    enableRedistributableFirmware = false;
    firmware = with pkgs; [
      wireless-regdb
      (runCommand "firmware-unio" {} ''
        mkdir -p $out/lib/firmware
        cp -r ${linux-firmware}/lib/firmware/tigon $out/lib/firmware
      '')
    ];
  };
}
