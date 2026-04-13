{
  id,
  main,
}: {
  boot.loader.grub = {
    efiInstallAsRemovable = true;
    efiSupport = true;
  };

  disko.devices = {
    disk = {
      main = {
        name = "main-${main}";
        device = "/dev/disk/by-id/${id}";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
              priority = 1;
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [
                  "--force"
                  "--label root"
                ];
                subvolumes = {
                  "@root" = {
                    mountpoint = "/";
                    mountOptions = [];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd"];
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Automatic local snapshots:
  # https://digint.ch/btrbk/doc/readme.html
  services.btrbk = {
    instances = {
      nix = {
        onCalendar = "*/2:00";
        settings = {
          subvolume = "/nix";
          snapshot_create = "onchange";
          snapshot_dir = "/nix";
          snapshot_preserve = "16h 7d 2w";
          snapshot_preserve_min = "3d";
        };
      };
      home = {
        onCalendar = "*/2:00";
        settings = {
          subvolume = "/home";
          snapshot_dir = "/home";
          snapshot_preserve = "16h 7d 3w 2m";
          snapshot_preserve_min = "3d";
        };
      };
    };
  };
}
