pkgs:
pkgs.talosctl.overrideAttrs (old: (let
  versions = import ../cluster/versions.nix;
  version = builtins.elemAt versions.talos.github-releases 1;
in {
  inherit version;
  src = fetchTarball {
    url = "https://github.com/siderolabs/talos/archive/refs/tags/v${version}.tar.gz";
    sha256 = "sha256:1956zvmra93y6vp531iyg274mvlm2nkpqcyncd2lh5gy1vbrjxg7";
  };
  vendorHash = "sha256-ocU7vpSdUdVzOFcqa+QWRdcP9SnC6WtV/ruheSGUfg4=";
}))
