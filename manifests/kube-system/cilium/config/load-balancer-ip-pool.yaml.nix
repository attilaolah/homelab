{
  self,
  k,
  ...
}:
k.api "CiliumLoadBalancerIPPool.cilium.io" (let
  inherit (self.lib) cluster;
in {
  metadata = {
    name = "${cluster.name}-ips";
    namespace = "kube-system";
  };
  spec.blocks = [{cidr = cluster.network.external.cidr4;}];
})
