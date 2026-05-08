{
  imports = [
    ./sshd.nix
    ./users.nix
  ];

  # Additional module imports by tag.
  # https://docs.clan.lol/latest/services/definition/
  inventory.instances = builtins.listToAttrs (let
    machineData = import ../data.nix;
    modules = ../../modules/tags;
    moduleNames = builtins.attrNames (builtins.readDir modules);
    hasTaggedMachines = tag:
      tag == "all" || (machineData.tags.${tag} or []) != [];
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
    }) (builtins.filter (module: hasTaggedMachines (builtins.replaceStrings [".nix"] [""] module)) moduleNames));
}
