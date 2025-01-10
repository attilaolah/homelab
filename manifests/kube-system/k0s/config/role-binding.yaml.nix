inputs @ {self, ...}: let
  inherit (self.lib) cluster;

  apiGroup = "rbac.authorization.k8s.io";
in {
  kind = "RoleBinding";
  apiVersion = "rbac.authorization.k8s.io/v1";
  metadata.name = "config-map-readers-alpine";

  subjects =
    map ({hostname, ...}: {
      kind = "User";
      name = "system:node:${hostname}";
      inherit apiGroup;
    })
    cluster.nodes.by.os.alpine;

  roleRef = let
    role = import ./role.yaml.nix inputs;
  in {
    inherit (role) kind;
    inherit (role.metadata) name;
    inherit apiGroup;
  };
}
