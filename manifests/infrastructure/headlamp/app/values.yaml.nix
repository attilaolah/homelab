# https://github.com/kubernetes-sigs/headlamp/blob/main/charts/headlamp/values.yaml
{
  k,
  lib,
  ...
}: let
  inherit (lib.strings) concatStringsSep;
  name = k.appname ./.;
in {
  inherit (k.container) securityContext;
  podSecurityContext = k.pod.securityContext;

  volumes = map (name: {
    inherit name;
    emptyDir = {};
  }) ["home" "tmp"];
  volumeMounts = [
    {
      name = "home";
      mountPath = "/home/${name}";
    }
    {
      name = "tmp";
      mountPath = "/tmp";
    }
  ];

  env = {
    OIDC_CLIENT_ID = name;
    OIDC_ISSUER_URL = "todo";
    OIDC_SCOPES = concatStringsSep " " [
      "email"
      "openid"
      "profile"
    ];
  };

  config = {
    baseURL = "/${name}";
    oidc = {
      secret.create = false;
      externalSecret = {
        enabled = true;
        name = "${name}-secrets";
      };
    };
  };
}
