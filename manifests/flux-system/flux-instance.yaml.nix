{
  self,
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
      inherit (import ./source.nix) kind;
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
})
