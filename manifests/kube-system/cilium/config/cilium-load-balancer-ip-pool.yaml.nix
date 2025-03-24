{
  cluster,
  k,
  ...
}:
k.api "CiliumLoadBalancerIPPool.cilium.io" {
  metadata = {
    name = "${cluster.name}-ips";
    namespace = "kube-system";
  };
  spec.blocks = [{cidr = cluster.network.external.cidr4;}];
}
