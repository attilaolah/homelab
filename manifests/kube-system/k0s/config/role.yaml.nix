inputs @ {k, ...}:
k.api "Role.rbac.authorization.k8s.io" (let
  k8sapi = (import ./k8sapi.nix) inputs;
in {
  metadata.name = "config-map-reader";
  rules = [
    {
      apiGroups = [""];
      resources = ["configmaps"];
      resourceNames = ["worker-config-alpine-${k8sapi}"];
      verbs = ["get" "list"];
    }
  ];
})
