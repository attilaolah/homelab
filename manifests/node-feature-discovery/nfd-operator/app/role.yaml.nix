{k, ...}:
# TODO: Remove when issue below is resolved:
# https://github.com/kubernetes-sigs/node-feature-discovery-operator/issues/262
k.api "Role.rbac.authorization.k8s.io" {
  metadata.name = "nfd-reader";
  rules = [
    {
      apiGroups = ["nfd.kubernetes.io"];
      resources = ["nodefeaturediscoveries"];
      verbs = ["get" "list" "watch"];
    }
  ];
}
