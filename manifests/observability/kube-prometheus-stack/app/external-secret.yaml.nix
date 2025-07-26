{
  k,
  self,
  ...
}: let
  inherit (self.lib) yaml;
in
  k.external-secret ./. {
    data = {
      grafana_admin_user = "admin";
      grafana_admin_password = "{{ .grafana_admin_password }}";
      oauth2_client_secret = "{{ .monitoring_client_secret }}";
      oauth2_cookie_secret = "{{ .prometheus_cookie_secret }}";

      # Additional Helm values:
      "values.yaml" = yaml.format {};
    };
  }
