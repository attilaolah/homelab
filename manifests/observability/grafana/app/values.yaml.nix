inputs @ {k, ...}: let
  hostname = k.hostname ./.;
  issuer = import ../../../cert-manager/cert-manager/config/cluster-issuer.yaml.nix inputs;
  certificate = import ../../../ingress-nginx/ingress-nginx/config/certificate.yaml.nix inputs;
in {
  # Expose Grafana via an ingress path on the default hostname.
  ingress = let
    hosts = [hostname];
  in {
    inherit hosts;

    enabled = true;

    ingressClassName = "nginx";
    annotations = {
      # TLS
      "cert-manager.io/cluster-issuer" = issuer.metadata.name;
      # Homepage
      "gethomepage.dev/enabled" = "true";
      "gethomepage.dev/name" = "Grafana";
      "gethomepage.dev/description" = "Observability platform";
      "gethomepage.dev/group" = "Cluster Management";
      "gethomepage.dev/icon" = "grafana.png";
      # TODO: Homepage widget type
      # "gethomepage.dev/widget.type" = "grafana";
      # "gethomepage.dev/widget.username" = "homepage";
      # "gethomepage.dev/widget.password" = "{{HOMEPAGE_VAR_GRAFANA_PASSWORD}}";
    };
    tls = [
      {
        inherit hosts;
        inherit (certificate.spec) secretName;
      }
    ];
  };

  # Allow spinning up a second replica. The default number of replicas is 1.
  autoscaling = {
    enabled = true;
    maxReplicas = 2;
  };
  podDisruptionBudget.minAvailable = 1;

  # Grafana's primary configuration.
  "grafana.ini".server.enforce_domain = true;

  datasources."datasources.yaml" = {
    apiVersion = 1;
    datasources = [
      {
        name = "Loki";
        type = "loki";
        url = "http://loki:3100";
      }
    ];
    prune = true;
  };
}
