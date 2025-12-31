pkgs:
pkgs.talosctl.overrideAttrs (old: (let
  versions = import ../cluster/versions.nix;
  version = builtins.elemAt versions.talos.github-releases 1;
in {
  inherit version;
  src = fetchTarball {
    url = "https://github.com/siderolabs/talos/archive/refs/tags/v${version}.tar.gz";
    sha256 = "sha256:0hj6qdiiv1vpmw52wwirgml7qfi3hlps13chdkvn216nag9x7kxv";
  };
  vendorHash = "sha256-LLtbdKq028EEs8lMt3uiwMo2KMJ6nJKf6xFyLJlg+oM=";
}))
