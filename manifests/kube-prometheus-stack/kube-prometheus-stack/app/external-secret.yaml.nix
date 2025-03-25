{
  k,
  self,
  ...
}: let
  inherit (self.lib) yaml;
in
  k.external-secret ./. {
    data = {
      grafana-admin-user = "admin";
      grafana-admin-password = "{{ .grafana_admin_password }}";
      oauth2-client-secret = "{{ .monitoring_client_secret }}";

      # Additional Helm values:
      "values.yaml" = yaml.format {};
    };
  }
