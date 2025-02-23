{
  cluster,
  k,
  lib,
  ...
}: {
  grafana = let
    inherit (builtins) attrValues mapAttrs;
    inherit (cluster) domain;
    inherit (lib.strings) concatStringsSep;

    name = "grafana";
    path = "/${name}";
  in {
    ingress = let
      hosts = [domain];
    in {
      inherit hosts path;

      enabled = true;
      ingressClassName = "nginx";
      annotations = {
        # TLS
        "cert-manager.io/cluster-issuer" = "letsencrypt";
        # Homepage
        "gethomepage.dev/enabled" = "true";
        "gethomepage.dev/name" = "Grafana";
        "gethomepage.dev/description" = "Observability platform";
        "gethomepage.dev/group" = "Cluster Management";
        "gethomepage.dev/icon" = "${name}.svg";
        "gethomepage.dev/pod-selector" =
          concatStringsSep ","
          (attrValues (mapAttrs (key: val: "app.kubernetes.io/${key}=${val}") {
            inherit name;
            instance = k.appname ./.;
          }));
      };
      tls = [
        {
          inherit hosts;
          secretName = "${domain}-tls";
        }
      ];
    };

    admin = let
      prefix = "${name}-admin";
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
