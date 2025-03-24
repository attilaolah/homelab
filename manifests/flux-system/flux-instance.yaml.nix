{
  cluster,
  k,
  v,
  ...
}:
k.api "FluxInstance.fluxcd.controlplane.io" (let
  name = "flux";
in {
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
      url = with cluster.github; "oci://${registry}/${owner}/${repository}";
      ref = "latest";
      path = ".";
      pullSecret = "oci-auth";
    };
    cluster = {
      type = "kubernetes";
      networkPolicy = true;
    };
  };
})
