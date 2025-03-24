{k, ...}:
# TODO: Remove when issue below is resolved:
# https://github.com/kubernetes-sigs/node-feature-discovery-operator/issues/262
k.api "RoleBinding.rbac.authorization.k8s.io" {
  metadata.name = "nfd-reader-binding";
  subjects = [
    {
      kind = "ServiceAccount";
      name = "default";
      namespace = k.nsname ./.;
    }
  ];
  roleRef = {
    kind = "Role";
    name = "nfd-reader";
    apiGroup = "rbac.authorization.k8s.io";
  };
}
