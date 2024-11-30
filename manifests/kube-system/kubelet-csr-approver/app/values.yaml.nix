{self, ...}: let
  inherit (self.lib) cluster;
in {
  providerRegex = "^${cluster.name}-\\d{2}$";
  providerIpPrefixes = with cluster.network.node; "${cidr4Strict},${cidr6}";
  bypassDnsResolution = true;
}