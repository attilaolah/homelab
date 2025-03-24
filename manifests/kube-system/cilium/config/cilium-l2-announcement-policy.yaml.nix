{
  cluster,
  k,
  ...
}:
k.api "CiliumL2AnnouncementPolicy.cilium.io" {
  metadata.name = "${cluster.name}-ips-l2-policy";
  spec = {
    loadBalancerIPs = true;
    nodeSelector.matchLabels."kubernetes.io/arch" = "amd64";
  };
}
