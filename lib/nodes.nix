{
  lib,
  self,
}: dir:
map (src: let
  inherit (lib.strings) removeSuffix toIntBase10;
  inherit (self.lib) cluster eui64;
  inherit (cluster.network) node;

  defaults = {
    controlPlane = false;
  };

  data = defaults // (import src);
  index = removeSuffix ".nix" (baseNameOf src);

  pre4 = builtins.substring 0 (builtins.stringLength node.net4 - 2) node.net4;
  ipv4 = "${pre4}.${toString (toIntBase10 index)}";
  ipv6 = eui64 node.net6 data.mac;

  extras = {
    inherit ipv4 ipv6;

    hostname = "${cluster.name}-${index}";
    net4 = "${ipv4}/${toString node.net4LenRoutable}";
    net6 = "${ipv6}/${toString node.net6Len}";

    # Defaults:
    zfs = false;
    watchdog = true;
  };
in
  extras // data) (lib.fileset.toList dir)
