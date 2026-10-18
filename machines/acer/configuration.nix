{
  imports = [../../modules/firmware.nix];

  firmware = {
    file = ./firmware.txt;
    wifi = true;
  };
}
