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
    # Add the Clan cli tool to the dev shell.
    # Use "nix develop" to enter the dev shell.
    devShells =
      nixpkgs.lib.genAttrs
      [
        "x86_64-linux"
        "aarch64-darwin"
      ]
      (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        intermediateCaExt = ./modules/tags/tpm12/templates/intermediate-ca.ext;
        tpm-tls-sign = pkgs.writeShellApplication {
          name = "tpm-tls-sign";
          runtimeInputs = [
            clan-core.packages.${system}.clan-cli
            pkgs.coreutils
            pkgs.openssl
          ];
          text = ''
            set -euo pipefail

            if [[ $# -ne 1 ]]; then
              echo "usage: tpm-tls-sign <machine>" >&2
              exit 2
            fi

            machine=$1
            work="$(mktemp -d "/tmp/tpm-tls-sign-$machine.XXXXXX")"
            root_key="$work/root-ca.key"
            csr="$work/ca.csr"
            crt="$work/ca.crt"
            key="$work/ca.key"
            serial="$work/ca.srl"

            cleanup() {
              rm -f "$root_key"
            }
            trap cleanup EXIT

            # Avoid PTY line-ending conversion while fetching files through clan ssh.
            clan ssh "$machine" -c base64 -w0 /var/lib/pki/tpm/ca.csr |
              base64 -d > "$csr"
            clan ssh "$machine" -c base64 -w0 /var/lib/pki/tpm/ca.key |
              base64 -d > "$key"

            clan vars get "$machine" tls-ca/ca.key > "$root_key"

            openssl x509 \
              -req \
              -in "$csr" \
              -CA vars/shared/tls-ca/ca.crt/value \
              -CAkey "$root_key" \
              -CAserial "$serial" \
              -CAcreateserial \
              -out "$crt" \
              -days 1825 \
              -sha256 \
              -extfile ${intermediateCaExt}

            openssl verify -CAfile vars/shared/tls-ca/ca.crt/value "$crt"

            clan vars set "$machine" tpm/ca.key < "$key"
            clan vars set "$machine" tpm/ca.crt < "$crt"
            clan vars fix "$machine"

            echo "stored tpm/ca.key and tpm/ca.crt for $machine"
            echo "temporary files kept in $work"
          '';
        };
      in {
        default = pkgs.mkShell {
          packages = [
            clan-core.packages.${system}.clan-cli
            tpm-tls-sign
          ];
        };
      });
  };
}
