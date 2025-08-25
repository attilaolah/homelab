# https://github.com/kubernetes-sigs/headlamp/blob/main/charts/headlamp/values.yaml
{
  cluster,
  k,
  lib,
  self,
  v,
  ...
}: let
  inherit (cluster) domain;
  inherit (lib.strings) concatStringsSep;
  inherit (self.lib) yaml;
  name = k.appname ./.;
in {
  inherit (k.container) securityContext;
  podSecurityContext = k.pod.securityContext;

  image.tag = v.headlamp.docker;

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
      value = "https://${domain}/keycloak/realms/dh";
    }
    {
      name = "OIDC_SCOPES";
      value = concatStringsSep "," [
        "email"
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
            path = "/${name}";
            type = "Prefix";
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

  resources = let
    requests = {
      cpu = "200m";
      memory = "256Mi";
      ephemeral-storage = "1Gi";
    };
  in {
    inherit requests;
    limits = requests // {cpu = "1";};
  };

  extraManifests = map yaml.format [
    (k.external-secret ./. {data.OIDC_CLIENT_SECRET = "{{`{{ .headlamp_client_secret }}`}}";})
  ];
}
