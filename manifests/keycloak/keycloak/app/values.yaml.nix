# https://artifacthub.io/packages/helm/bitnami/keycloak#parameters
{
  k,
  cluster,
  ...
}: let
  inherit (cluster) domain;

  name = k.appname ./.;
  namespace = k.nsname ./.;

  path = "/${name}";
in {
  production = true;

  # Use our own database.
  postgresql.enabled = false;
  # CloudNative PG managed cluster.
  externalDatabase = {
    existingSecret = "${k.fluxcd.ksname ../database}-app";
    existingSecretHostKey = "host";
    existingSecretPortKey = "port";
    existingSecretUserKey = "user";
    existingSecretDatabaseKey = "dbname";
    existingSecretPasswordKey = "password";
  };

  tls = {
    enabled = true;
    existingSecret = "${name}-tls";
  };

  # TODO: Configure mTLS between ingress controller & keycloak: https://www.keycloak.org/server/mutual-tls
  ingress = {
    inherit path;

    enabled = true;
    ingressClassName = "nginx";
    hostname = domain;
    annotations = with k.annotations;
      cert-manager
      // (ingress-nginx {
        inherit name namespace;
        secret = "${name}-crt";
      })
      // (homepage {
        name = "Keycloak";
        description = "Identity provider";
        group = "Cluster Management";
        icon = name;
        href = "/${name}/realms/dh/account";
      });

    tls = true;
    servicePort = "https";
  };
  proxyHeaders = "forwarded";
  httpRelativePath = "${path}/";
}
