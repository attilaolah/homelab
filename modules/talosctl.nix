pkgs:
pkgs.talosctl.overrideAttrs (old: (let
  versions = import ../cluster/versions.nix;
  version = builtins.elemAt versions.talos.github-releases 1;
in {
  inherit version;
  src = fetchTarball {
    url = "https://github.com/siderolabs/talos/archive/refs/tags/v${version}.tar.gz";
    sha256 = "0snz8hs92lx858w0iwn6plc46p1n85wbwrcrr0fpaf0d04mb8yga";
  };
  vendorHash = "sha256-NLyWzkagiP6zeeB4o6CI9UBPH6a5JGhPu1QGyiovBfM=";
}))
