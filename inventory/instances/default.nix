{
  imports = [
    ./sshd.nix
    ./users.nix
  ];

  # Additional module imports by tag.
  # https://docs.clan.lol/latest/services/definition/
  inventory.instances = builtins.listToAttrs (map (module: let
    tag = builtins.replaceStrings [".nix"] [""] module;
  in {
    name = "settings-${tag}";
    value = {
      module.name = "importer";
      roles.default = {
        tags.${tag} = {};
        extraModules = [../../modules/tags/${module}];
      };
    };
  }) (builtins.attrNames (builtins.readDir ../../modules/tags)));
}
