ctx:
builtins.attrValues (
  builtins.mapAttrs (name: spec: {
    kind = "Kustomization";
    apiVersion = "kustomize.toolkit.fluxcd.io/v1";
    metadata = {
      inherit name;
      namespace = "flux-system";
    };
    spec =
      {
        targetNamespace = "kube-system";
        commonMetadata.labels."app.kubernetes.io/name" = name;
        prune = false; # should never be deleted
        sourceRef = let
          repo = import ../../flux-system/oci-repository.yaml.nix ctx;
        in {
          inherit (repo) kind;
          inherit (repo.metadata) name;
        };
        wait = true;
        interval = "30m";
        retryInterval = "1m";
        timeout = "5m";
      }
      // spec;
  })
  {
    cilium = {
      path = "./kube-system/cilium/app";
    };
    cilium-config = {
      path = "./kube-system/cilium/config";
      dependsOn = [
        {
          name = "cilium";
          namespace = "flux-system";
        }
      ];
    };
  }
)