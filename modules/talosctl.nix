pkgs:
pkgs.talosctl.overrideAttrs (old: (let
  versions = import ../cluster/versions.nix;
  version = builtins.elemAt versions.talos.github-releases 1;
in {
  inherit version;
  src = fetchTarball {
    url = "https://github.com/siderolabs/talos/archive/refs/tags/v${version}.tar.gz";
    sha256 = "0fv828api36pvw6f82w6r1ihrvj00iklszsgn4mg59v48zajxsqv";
  };
  vendorHash = "sha256-x9In+TaEuYMB0swuMzyXQRRnWgP1Krg7vKQH4lqDf+c=";
}))
