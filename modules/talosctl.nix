pkgs:
pkgs.talosctl.overrideAttrs (old: (let
  versions = import ../cluster/versions.nix;
  version = builtins.elemAt versions.talos.github-releases 1;
in {
  inherit version;
  src = fetchTarball {
    url = "https://github.com/siderolabs/talos/archive/refs/tags/v${version}.tar.gz";
    sha256 = "06rn4vjfgwvy1v63xrrjiwjgp467lrv9j9cdvv473b0yfpa6gr1h";
  };
  vendorHash = "sha256-6UVhWh53pHo6xZOXw/uncDL1AvnsFG27G4FX/qPfedU=";
}))
