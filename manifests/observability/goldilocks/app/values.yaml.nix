# https://artifacthub.io/packages/helm/fairwinds-stable/goldilocks#values
# https://github.com/FairwindsOps/charts/blob/master/stable/goldilocks/values.yaml
{
  k,
  v,
  ...
}: let
  name = k.appname ./.;
  resources = let
    requests = {
      cpu = "50m";
      memory = "256Mi";
      ephemeral-storage = "256Mi";
    };
  in {
    inherit requests;
    limits = requests // {cpu = "1";};
  };
in {
  image.tag = v.goldilocks.docker;

  controller = {
    inherit resources;
    flags.on-by-default = "true";
  };

  dashboard = {
    inherit resources;
    basePath = "/${name}";
    flags = {
      on-by-default = "true";
      enable-cost = "false";
    };
  };
}
