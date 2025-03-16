{
  nixpkgs-devenv,
  withSystem,
  ...
}: {self, ...}: {
  perSystem = {
    system,
    inputs',
    pkgs,
    ...
  }: let
    env = "TASKFILE";
    taskfile-yaml = self.lib.yaml.write ./taskfile.yaml.nix {inherit inputs' pkgs;};
    task-wrapper = pkgs.writeShellApplication {
      name = "task";
      runtimeInputs = with pkgs; [go-task];
      text = ''
        task --taskfile="''$${env}" "$@"
      '';
    };
  in {
    devenv.shells.default = {
      env.${env} = taskfile-yaml;
      packages = [task-wrapper];
    };
  };
}
