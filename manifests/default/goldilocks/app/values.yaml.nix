# https://artifacthub.io/packages/helm/fairwinds-stable/goldilocks#values
# https://github.com/FairwindsOps/charts/blob/master/stable/goldilocks/values.yaml
{
  k,
  v,
  ...
}: let
  name = k.appname ./.;
in {
  image.tag = v.goldilocks.docker;
  controller.resources = rec {
    limits = requests // {cpu = "200m";};
    requests = {
      cpu = "50m";
      memory = "256Mi";
      ephemeral-storage = "256Mi";
    };
  };
  dashboard = {
    basePath = "/${name}";
    flags.enable-cost = "false";
    resources = rec {
      limits = requests // {cpu = "100m";};
      requests = {
        cpu = "50m";
        memory = "128Mi";
        ephemeral-storage = "128Mi";
      };
    };
  };
}
