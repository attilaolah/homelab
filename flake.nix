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
    nixpkgs-devenv.url = "github:cachix/devenv-nixpkgs/rolling";

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
    nixpkgs-devenv,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} (ctx @ {
      withSystem,
      flake-parts-lib,
      ...
    }: let
      inherit (flake-parts-lib) importApply;
      flakeModules = {
        taskfiles = importApply ./taskfiles ctx;
        taskfiles-sops = importApply ./taskfiles/sops.nix ctx;
        taskfiles-talos = importApply ./taskfiles/talos.nix ctx;
      };
    in {
      systems = ["x86_64-linux"];
      imports = [inputs.devenv.flakeModule] ++ builtins.attrValues flakeModules;

      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        pkgs-devenv = import nixpkgs-devenv {inherit system;};

        talhelper = inputs'.talhelper.packages.default;

        params = {pkgs = pkgs // {inherit talhelper;};};
        inventory-yaml = import ./ansible/inventory.nix params;
        talconfig-yaml = import ./talos/talconfig.nix params;

        task-wrapper = pkgs.writeShellScriptBin "task" ''
          ${pkgs.lib.getExe' pkgs-devenv.go-task "task"} --taskfile=${self'.packages.taskfile-yaml} $@
        '';
      in {
        packages.default = task-wrapper;
        apps.default = {
          type = "app";
          program = pkgs.lib.getExe task-wrapper;
        };

        devenv.shells.default = {
          name = "homelab";
          devenv.root = let
            devenvRootFileContent = builtins.readFile devenv-root.outPath;
          in
            pkgs.lib.mkIf (devenvRootFileContent != "") devenvRootFileContent;

          imports = [
            # https://devenv.sh/guides/using-with-flake-parts/#import-a-devenv-module
          ];

          packages = with pkgs; [
            task-wrapper

            age
            alejandra
            ansible
            cilium-cli
            fluxcd
            helmfile
            jq
            kubectl
            sops
            talhelper
            talosctl
            yq
            yq-go

            (wrapHelm kubernetes-helm {
              plugins = with kubernetes-helmPlugins; [
                helm-diff
              ];
            })
          ];

          env = {
            ANSIBLE_INVENTORY = inventory-yaml;
            TALCONFIG = talconfig-yaml;
            TALSECRET = ./talos/talsecret.sops.yaml;
          };

          enterShell = ''
            export KUBECONFIG=$DEVENV_STATE/talos/kubeconfig
            export TALOSCONFIG=$DEVENV_STATE/talos/talosconfig
          '';
        };
      };
      flake = {inherit flakeModules;};
    });
}
