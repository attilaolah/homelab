{
  description = "Dornhaus Homelab";

  inputs = {
    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
    };

    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    talhelper.url = "github:budimanjojo/talhelper";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = inputs @ {
    self,
    flake-parts,
    devenv-root,
    nixpkgs,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} (ctx @ {
      withSystem,
      flake-parts-lib,
      ...
    }: let
      inherit (flake-parts-lib) importApply;
      flakeModules = {
        ansible = importApply ./modules/ansible ctx;
        manifests = importApply ./modules/manifests ctx;
        talhelper = importApply ./modules/talhelper ctx;
        task = importApply ./modules/task ctx;
      };
    in {
      systems = ["x86_64-linux"];
      imports = [inputs.devenv.flakeModule] ++ builtins.attrValues flakeModules;

      perSystem = {
        inputs',
        pkgs,
        self',
        ...
      }: let
        talhelper = inputs'.talhelper.packages.default;
      in {
        # The devenv shell.
        # Contains tooling and modules to effectively manage the cluster.
        devenv.shells.default = {
          devenv.root = let
            devenvRootFileContent = builtins.readFile devenv-root.outPath;
          in
            pkgs.lib.mkIf (devenvRootFileContent != "") devenvRootFileContent;

          packages = with pkgs; [
            (python3.withPackages (ps: with ps; [jmespath]))
            (wrapHelm kubernetes-helm {plugins = with kubernetes-helmPlugins; [helm-diff];})
            (talosctl.overrideAttrs (old: (let
              versions = import ./cluster/versions.nix;
              version = builtins.elemAt versions.talos.github-releases 1;
            in {
              inherit version;
              src = fetchTarball {
                url = "https://github.com/siderolabs/talos/archive/refs/tags/v${version}.tar.gz";
                sha256 = "06rn4vjfgwvy1v63xrrjiwjgp467lrv9j9cdvv473b0yfpa6gr1h";
              };
              vendorHash = "sha256-6UVhWh53pHo6xZOXw/uncDL1AvnsFG27G4FX/qPfedU=";
            })))

            age
            alejandra
            ansible
            cilium-cli
            fluxcd
            helmfile
            jq
            kube-capacity
            kubectl
            renovate
            sops
            talhelper
            vector
            yq
          ];

          enterShell = ''
            export KUBECONFIG="$DEVENV_STATE/talos/kubeconfig"
            export RENOVATE_CONFIG_FILE="$DEVENV_ROOT/.github/renovate.json"
            export TALOSCONFIG="$DEVENV_STATE/talos/talosconfig"
            export TALSECRET="$DEVENV_ROOT/talos/talsecret.sops.yaml"
          '';
        };
      };

      # Other flake contents.
      # Contains a library that is re-used by the modules.
      flake = {
        inherit flakeModules;
        lib = import ./lib {
          inherit self;
          inherit (nixpkgs) lib;
        };
      };
    });
}
