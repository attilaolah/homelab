{
  k,
  self,
  ...
}: let
  inherit (self.lib) yaml;
in
  k.external-secret ./. {
    data = {
      OIDC_CLIENT_SECRET = "{{ .headlamp_client_secret }}";

      # Additional Helm values:
      "values.yaml" = yaml.format {};
    };
  }
