{
  meta = {
    name = "locker";
    description = "Attila's bare metal homelab";
    domain = "dorn.haus";
  };

  inventory = {
    machines =
      builtins.mapAttrs (_: {
        # IP address suffix
        id,
        # Whether the host is currently connected to the "internal" network
        internal ? false,
        # Optional tags, see instances below
        tags ? [],
      }: let
        lan =
          if internal
          then 0
          else 1;
        ip = ip4 lan id;

        ip4 = x: y: "192.168.${toString x}.${toString y}";
      in {
        inherit tags;
        deploy.targetHost = "root@${ip}";
      }) {
        acer.id = 121;
        aloe.id = 116;
        ilex.id = 103;
        iris.id = 101;
        rosa.id = 120;
        unio.id = 117;

        # Laptops
        acer.tags = ["laptop"];
        rosa.tags = ["laptop"];
      };

    # https://docs.clan.lol/latest/services/definition/
    instances = {
      # https://docs.clan.lol/latest/services/official/sshd/
      sshd = {
        roles.server = {
          tags.all = {};
          settings.authorizedKeys = {
            # https://github.com/attilaolah.keys
            # All keys will have ssh access to all machines ("tags.all" means 'all machines').
            biometric = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP0Y/37XG4iBs4hHLI88dQQJhtVVal69GRF7HpHT+60J";
            home = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIiR17IcWh8l3OxxKSt+ODrUMLU98ZoJ+XvcR17iX9/P";
          };
        };
      };

      # https://docs.clan.lol/latest/services/official/users/
      user-root = {
        module.name = "users";
        roles.default = {
          tags.all = {};
          settings = {
            user = "root";
            prompt = true;
          };
        };
      };

      # Import shared NixOS snippets for all machines.
      common-settings = {
        module.name = "importer";
        roles.default = {
          tags.all = {};
          extraModules = [./modules/common.nix];
        };
      };

      # Import shared NixOS snippets for matching machine tags.
      laptop-settings = {
        module.name = "importer";
        roles.default = {
          tags.laptop = {};
          extraModules = [./modules/laptop.nix];
        };
      };
    };
  };
}
