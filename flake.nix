{
  inputs.clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
  inputs.nixpkgs.follows = "clan-core/nixpkgs";

  outputs = {
    self,
    clan-core,
    nixpkgs,
    ...
  } @ inputs: let
    # Usage see: https://docs.clan.lol
    domain = (import ./clan.nix).meta.domain;
    intermediateCaExt = ./modules/tags/tpm12/templates/intermediate-ca.ext;
    machineData = import ./inventory/data.nix;
    systems = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    overlays = [
      (import ./overlays/acme_eab_add.nix {inherit clan-core domain machineData;})
      (import ./overlays/tpm_tls_sign.nix {inherit clan-core intermediateCaExt;})
    ];
    homelabOverlay = nixpkgs.lib.composeManyExtensions overlays;
    pkgsForSystem = system:
      import nixpkgs {
        inherit system;
        inherit overlays;
      };
    clan = clan-core.lib.clan {
      inherit self;
      imports = [./clan.nix];
      specialArgs = {inherit inputs;};

      # Customize nixpkgs
      # pkgsForSystem =
      #   system:
      #   import nixpkgs {
      #     inherit system;
      #     config = {
      #       allowUnfree = true;
      #     };
      #     overlays = [];
      #   };
    };
  in {
    inherit (clan.config) nixosConfigurations nixosModules clanInternals;
    clan = clan.config;
    overlays.default = homelabOverlay;
    packages =
      forAllSystems
      (system: let
        pkgs = pkgsForSystem system;
      in {
        inherit (pkgs) acme-eab-add tpm-tls-sign;
      });
    # Add the Clan cli tool to the dev shell.
    # Use "nix develop" to enter the dev shell.
    devShells =
      forAllSystems
      (system: let
        pkgs = pkgsForSystem system;
      in {
        default = pkgs.mkShell {
          packages = [
            clan-core.packages.${system}.clan-cli
            pkgs.acme-eab-add
            pkgs.tpm-tls-sign
          ];
        };
      });
  };
}
