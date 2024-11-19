let
  name = "local-path-provisioner";
in {
  kind = "HelmRelease";
  apiVersion = "helm.toolkit.fluxcd.io/v2";
  metadata = {inherit name;};
  spec = {
    interval = "30m";
    chart.spec = {
      chart = "./deploy/chart/${name}";
      version = "v0.0.30";
      sourceRef = {
        inherit name;
        kind = "GitRepository";
        namespace = "flux-system";
      };
      interval = "12h";
    };
    install.remediation.retries = 3;
    upgrade = {
      cleanupOnFail = true;
      remediation.retries = 3;
    };
    valuesFrom = [
      {
        kind = "ConfigMap";
        name = "${name}-values";
      }
    ];
  };
}
