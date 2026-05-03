{
  imports = [
    ./sshd.nix
    ./users.nix
  ];

  # Additional module imports by tag.
  # https://docs.clan.lol/latest/services/definition/
  inventory.instances = builtins.listToAttrs (let
    modules = ../../modules/tags;
  in
    map (module: let
      tag = builtins.replaceStrings [".nix"] [""] module;
    in {
      name = "settings-${tag}";
      value = {
        module.name = "importer";
        roles.default = {
          tags.${tag} = {};
          extraModules = ["${modules}/${module}"];
        };
      };
    }) (builtins.attrNames (builtins.readDir modules)));
}
