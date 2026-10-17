{ pkgs, ... }: {
  imports = [../../modules/firmware.nix];

  boot.kernelPackages = pkgs.linuxPackages_latest;

  firmware = {
    file = ./firmware.txt;
    wifi = true;
  };
}
