# https://github.com/philippwaller/helm-charts/blob/main/charts/inadyn/values.yaml
{
  k,
  v,
  ...
}: {
  inherit (k.container) securityContext;

  image.tag = v.inadyn.docker;

  resources = let
    requests = {
      cpu = "20m";
      memory = "128Mi";
      ephemeral-storage = "128Mi";
    };
  in {
    inherit requests;
    limits = requests // {cpu = "1";};
  };
  podSecurityContext = k.pod.securityContext;
}
