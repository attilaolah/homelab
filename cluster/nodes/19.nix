{
  os = "alpine";
  mac = "00:22:64:b7:4e:50";

  cpu = "intel"; # Core 2 Duo E8500
  zfs = true;
  zfs_disks = [
    "wwn-0x50000395a2302056" # sdb
    "wwn-0x5000cca396f213a5" # sdc
  ];
}
