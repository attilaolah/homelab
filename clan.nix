{
  imports = [
    ./inventory/machines.nix
  ];

  meta = {
    name = "locker";
    description = "Attila's bare metal homelab";
    domain = "dorn.haus";
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
          home = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIiR17IcWh8l3OxxKSt+ODrUMLU98ZoJ+XvcR17iX9/P";
          macbook = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBC+mtV6yrvijOAmvsstRCYsUSbc8ZI3Np7qY2rWuACNaAnLSRhu5qbL/1EzZgcRFbMKaqRYLy8Tq56PDjck2MTo=";
          pixel = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCK3wit0j7rkD4q7DTAij1Swsk6zzCiJZyH6hthB+7Hou49XkEPbt3Obs6541x7LLD4v5XDo0CSm5QGSr2GgqJI=";
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
