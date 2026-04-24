{
  imports = [
    ./sshd.nix
    ./users.nix
  ];

  # Additional module imports by tag.
  # https://docs.clan.lol/latest/services/definition/
  inventory.instances = builtins.listToAttrs (map (tag: {
      name = "settings-${tag}";
      value = {
        module.name = "importer";
        roles.default = {
          tags.${tag} = {};
          extraModules = [../../modules/tags/${tag}.nix];
        };
      };
    }) [
      "all"
      "laptop"
    ]);
}
