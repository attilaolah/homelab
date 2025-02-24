{
  self,
  k,
  ...
}: let
  inherit (self.lib) yaml;
in
  k.external-secret ./. {
    data = {
      oauth2-client-secret = "{{ .jaeger_ui_client_secret }}";
      oauth2-cookie-secret = "{{ .jaeger_ui_cookie_secret }}";

      # Additional Helm values:
      "values.yaml" = yaml.format {};
    };
  }
