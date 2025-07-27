{
  k,
  self,
  ...
}: let
  inherit (self.lib) yaml;
in
  k.external-secret ./. {
    data = {
      oauth2_client_secret = "{{ .monitoring_client_secret }}";
      oauth2_cookie_secret = "{{ .jaeger_cookie_secret }}";
      oauth2_redis_password = "{{ .redis_oauth_db_password }}";

      # Additional Helm values:
      "values.yaml" = yaml.format {};
    };
  }
