{
  imports = [
    ./sshd.nix
    ./users.nix
  ];

  # Additional module imports by tag.
  # https://docs.clan.lol/latest/services/definition/
  inventory.instances =
    builtins.mapAttrs (tag: extraModules: {
      module.name = "importer";
      roles.default = {
        inherit extraModules;
        tags.${tag} = {};
      };
    }) {
      all = [../../modules/common.nix];
      laptop = [../../modules/laptop.nix];
    };
}
