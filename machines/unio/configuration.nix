{pkgs, ...}: {
  imports = [];

  hardware = {
    enableRedistributableFirmware = false;
    firmware = with pkgs; [
      wireless-regdb
      (runCommand "firmware-tigon" {} ''
        mkdir -p $out/lib/firmware
        cp ${linux-firmware}/lib/firmware/tigon $out/lib/firmware
      '')
    ];
  };
}
