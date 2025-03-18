{
  os = "alpine";
  mac = "00:26:2d:37:67:fd";

  cpu = "amd"; # Athlon II X2 215
  watchdog = false;
  zfs = true;
  zfs_disks = [
    "wwn-0x5000c5007946e59f" # sdb
  ];
}
