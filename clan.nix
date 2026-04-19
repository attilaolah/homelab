let
  ip4 = x: y: "192.168.${toString x}.${toString y}";
  # internal = ip4 0;
  dmz = ip4 1;
in {
  meta = {
    name = "locker";
    description = "Attila's bare metal homelab";
    domain = "dorn.haus";
  };

  inventory.machines = {
    acer = {
      deploy.targetHost = "root@${dmz 121}";
      tags = ["laptop"];
    };
    ilex = {
      deploy.targetHost = "root@${dmz 103}";
      tags = [];
    };
    iris = {
      deploy.targetHost = "root@${dmz 101}";
      tags = [];
    };
    rosa = {
      deploy.targetHost = "root@${dmz 120}";
      tags = ["laptop"];
    };
  };

  # https://docs.clan.lol/latest/services/definition/
  inventory.instances = {
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
}
