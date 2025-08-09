# https://github.com/kubernetes-sigs/headlamp/blob/main/charts/headlamp/values.yaml
{
  cluster,
  k,
  lib,
  ...
}: let
  inherit (cluster) domain;
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

  env = [
    {
      name = "OIDC_CLIENT_ID";
      value = name;
    }
    {
      name = "OIDC_ISSUER_URL";
      value = "todo";
    }
    {
      name = "OIDC_SCOPES";
      value = concatStringsSep " " [
        "email"
        "openid"
        "profile"
      ];
    }
  ];

  ingress = {
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
    annotations = k.annotations.cert-manager;
    tls = [
      {
        hosts = [domain];
        secretName = "${domain}-tls";
      }
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
