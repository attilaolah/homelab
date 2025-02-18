inputs @ {
  cluster,
  v,
  ...
}: let
  inherit (cluster) domain;

  title = "Dornhaus";

  issuer = import ../../../cert-manager/cert-manager/config/cluster-issuer.yaml.nix inputs;
  certificate = import ../../../ingress-nginx/ingress-nginx/config/certificate.yaml.nix inputs;
in {
  config = {
    settings = {
      inherit title;
      theme = "dark";
      color = "gray";

      layout."Cluster Management" = {
        style = "row";
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
    kubernetes.mode = "cluster";
  };

  enableRbac = true;
  serviceAccount.create = true;

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
    annotations."cert-manager.io/cluster-issuer" = issuer.metadata.name;
    tls = [
      {
        hosts = [domain];
        inherit (certificate.spec) secretName;
      }
    ];
  };

  # Use Loki for logs, no need to persist a local copy.
  persistence.logs.enabled = false;

  resources = {
    requests = {
      cpu = "20m";
      memory = "64Mi";
    };
    limits = {
      cpu = "500m";
      memory = "256Mi";
    };
  };

  # TODO:
  # env.HOMEPAGE_VAR_GRAFANA_PASSWORD.valueFrom.secretKeyRef = {
  #   name = "homepage-secrets";
  #   key = "grafana-password";
  # };

  image.tag = v.homepage.docker;
}
