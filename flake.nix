{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-patcher.url = "github:gepbird/nixpkgs-patcher";

    acme-eab = {
      url = "github:attilaolah/acme-eab/v0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    clan-core,
    nixpkgs,
    ...
  } @ inputs: let
    inherit (builtins) toString;

    # Usage see: https://docs.clan.lol
    domain = (import ./clan.nix).meta.domain;
    intermediateCaExt = toString ./modules/tags/tpm12/templates/intermediate_ca.ext;
    machineData = import ./inventory/data.nix;

    overlays = [
      (import ./overlays/acme_db_seal.nix {inherit clan-core;})
      (import ./overlays/acme_provision.nix {inherit clan-core domain machineData;})
      (import ./overlays/tpm_tls_sign.nix {inherit clan-core intermediateCaExt;})
    ];

    forAllSystems = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    pkgsForSystem = system:
      import nixpkgs {
        inherit system;
        inherit overlays;
      };
    clan = clan-core.lib.clan {
      inherit self;
      imports = [./clan.nix];
      specialArgs = {inherit inputs;};
    };
  in {
    inherit (clan.config) nixosConfigurations nixosModules clanInternals;

    clan = clan.config;
    overlays.default = nixpkgs.lib.composeManyExtensions overlays;

    packages =
      forAllSystems
      (system: {
        inherit
          (pkgsForSystem system)
          acme-db-seal
          acme-provision
          tpm-tls-sign
          ;
      });

    # Add the Clan cli tool to the dev shell.
    # Use "nix develop" to enter the dev shell.
    devShells =
      forAllSystems
      (system: let
        pkgs = pkgsForSystem system;
      in {
        default = pkgs.mkShell {
          packages =
            [clan-core.packages.${system}.clan-cli]
            ++ (with pkgs; [
              acme-db-seal
              acme-provision
              tpm-tls-sign
            ]);
        };
      });
  };
}
