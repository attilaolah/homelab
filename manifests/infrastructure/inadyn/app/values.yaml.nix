# https://github.com/philippwaller/helm-charts/blob/main/charts/inadyn/templates/deployment.yaml
{
  k,
  v,
  ...
}: {
  inherit (k.container) securityContext;

  image.tag = v.inadyn.docker;

  resources = let
    guaranteed = {
      cpu = "20m";
      memory = "128Mi";
      ephemeral-storage = "128Mi";
    };
  in {
    limits = guaranteed;
    requests = guaranteed;
  };
  podSecurityContext = k.pod.securityContext;
}
