{self, ...}: let
  inherit (builtins) listToAttrs map;
  inherit (self.lib) cluster;

  clusterGroup = group:
    listToAttrs (map (value @ {
        hostname,
        ipv4,
        ...
      }: {
        name = hostname;
        value = value // {ansible_host = ipv4;};
      })
      group);
in {
  alpine = {
    hosts = clusterGroup cluster.nodes.by.os.alpine;
    vars = {
      inherit (cluster) network;
      cluster = {inherit (cluster) domain name;};
    };
  };
}
