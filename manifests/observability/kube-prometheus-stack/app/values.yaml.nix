inputs @ {
  cluster,
  k,
  ...
}: let
  issuer = import ../../../cert-manager/cert-manager/config/cluster-issuer.yaml.nix inputs;
  certificate = import ../../../ingress-nginx/ingress-nginx/config/certificate.yaml.nix inputs;
in {
  grafana = let
    inherit (cluster) domain;
    path = "/grafana";
  in {
    # Expose Grafana via an ingress path on the default hostname.
    ingress = let
      hosts = [domain];
    in {
      inherit hosts path;

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
        "gethomepage.dev/pod-selector" = "app.kubernetes.io/name=grafana";
      };
      tls = [
        {
          inherit hosts;
          inherit (certificate.spec) secretName;
        }
      ];
    };

    admin = let
      prefix = "grafana-admin";
    in {
      userKey = "${prefix}-user";
      passwordKey = "${prefix}-password";
      existingSecret = "${k.appname ./.}-secrets";
    };

    # Grafana's primary configuration.
    "grafana.ini".server = {
      enforce_domain = true;
      serve_from_sub_path = true;
      root_url = "https://${domain}${path}";
    };

    additionalDataSources = [
      {
        name = "Loki";
        type = "loki";
        url = "http://loki:3100";
      }
    ];
  };

  cleanPrometheusOperatorObjectNames = true;
}
