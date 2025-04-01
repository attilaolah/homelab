# https://github.com/jameswynn/helm-charts/blob/main/charts/homepage/values.yaml
{
  cluster,
  k,
  v,
  ...
}: let
  inherit (cluster) domain;

  title = "Dornhaus";
in {
  inherit (k.container) securityContext;

  config = {
    settings = {
      inherit title;
      theme = "dark";
      color = "gray";

      layout."Cluster Management" = {
        style = "row";
        icon = "kubernetes.svg";
        columns = 4;
      };
    };
    services = [];
    bookmarks = [];
    widgets = [
      {
        greeting = {
          text = title;
          text_size = "4xl";
        };
      }
      {
        kubernetes = {
          cluster = {
            show = true;
            cpu = true;
            memory = true;
            showLabel = true;
            label = "/locker/";
          };
          nodes = {
            show = true;
            cpu = true;
            memory = true;
            showLabel = true;
          };
        };
      }
    ];
    kubernetes = {
      mode = "cluster";
      ingress = true;
    };
  };

  enableRbac = true;
  serviceAccount.create = true;
  podSecurityContext = k.pod.securityContext;

  ingress.main = {
    enabled = true;
    ingressClassName = "nginx";
    hosts = [
      {
        host = domain;
        paths = [
          {
            path = "/";
            pathType = "Prefix";
          }
        ];
      }
    ];
    annotations = k.annotations.cert-manager;
    tls = [
      {
        hosts = [domain];
        secretName = "${domain}-tls";
      }
    ];
  };

  # Use Loki for logs, no need to persist a local copy.
  persistence.logs.enabled = false;

  resources = let
    guaranteed = {
      cpu = "200m";
      memory = "256Mi";
      ephemeral-storage = "128Mi";
    };
  in {
    limits = guaranteed;
    requests = guaranteed;
  };

  env.HOMEPAGE_ALLOWED_HOSTS = cluster.domain;

  image.tag = v.homepage.docker;
}
