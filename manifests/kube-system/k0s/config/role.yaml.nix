inputs: let
  version = (import ./versions.nix).k8sapi inputs;
in {
  kind = "Role";
  apiVersion = "rbac.authorization.k8s.io/v1";
  metadata.name = "config-map-reader";
  rules = [
    {
      apiGroups = [""];
      resources = ["configmaps"];
      resourceNames = ["worker-config-alpine-${version}"];
      verbs = ["get" "list"];
    }
  ];
}
