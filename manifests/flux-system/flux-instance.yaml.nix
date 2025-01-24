{
  self,
  v,
  ...
}: let
  name = "flux";
in {
  kind = "FluxInstance";
  apiVersion = "fluxcd.controlplane.io/v1";
  metadata = {
    inherit name;
    namespace = "flux-system";
  };
  spec = {
    distribution = {
      version = v.${name}.github-releases;
      registry = "ghcr.io/fluxcd";
      artifact = "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests";
    };
    sync = {
      kind = "OCIRepository";
      url = with self.lib.cluster.github; "oci://${registry}/${owner}/${repository}";
      ref = "latest";
      path = ".";
      pullSecret = "ghcr-auth";
    };
    cluster = {
      type = "kubernetes";
      networkPolicy = true;
    };
  };
}
