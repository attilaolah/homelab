{cluster, ...}: {
  providerRegex = "^${cluster.name}-\\d{2}$";
  providerIpPrefixes = with cluster.network.node; "${cidr4},${cidr6}";
  bypassDnsResolution = true;
}
