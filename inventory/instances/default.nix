{
  imports = [
    ./sshd.nix
  ];
  # https://docs.clan.lol/latest/services/definition/
  inventory.instances =
    {
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
    }
    # Additional module imports by tag.
    // (builtins.mapAttrs (tag: extraModules: {
        module.name = "importer";
        roles.default = {
          inherit extraModules;
          tags.${tag} = {};
        };
      }) {
        all = [../../modules/common.nix];
        laptop = [../../modules/laptop.nix];
      });
}
