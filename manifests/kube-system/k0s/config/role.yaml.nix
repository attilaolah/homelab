inputs: let
  k8sapi = (import ./_k8s_api.nix) inputs;
in {
  kind = "Role";
  apiVersion = "rbac.authorization.k8s.io/v1";
  metadata.name = "config-map-reader";
  rules = [
    {
      apiGroups = [""];
      resources = ["configmaps"];
      resourceNames = ["worker-config-alpine-${k8sapi}"];
      verbs = ["get" "list"];
    }
  ];
}
