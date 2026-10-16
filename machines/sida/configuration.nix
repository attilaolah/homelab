{
  lib,
  pkgs,
  ...
}: {
  imports = [../../modules/firmware.nix];
  firmware = {
    file = ./firmware.txt;
    src = [pkgs.linux-firmware pkgs.b43Firmware_6_30_163_46];
    wifi = true;
  };
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "b43-firmware";
}
