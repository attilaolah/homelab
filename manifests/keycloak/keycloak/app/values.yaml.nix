# https://artifacthub.io/packages/helm/bitnami/keycloak#parameters
inputs @ {
  k,
  cluster,
  ...
}: let
  inherit (cluster) domain;
  issuer = import ../../../cert-manager/cert-manager/config/cluster-issuer.yaml.nix inputs;
  certificate = import ../../../ingress-nginx/ingress-nginx/config/certificate.yaml.nix inputs;

  name = k.appname ./.;
in {
  production = false; # todo

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
    autoGenerated = true;
  };

  ingress = {
    enabled = true;
    ingressClassName = "nginx";
    hostname = domain;
    path = "/${name}/";
    annotations = {
      # TLS
      "cert-manager.io/cluster-issuer" = issuer.metadata.name;
      # NGINX
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$1";
      # "nginx.ingress.kubernetes.io/configuration-snippet" = ''
      #   rewrite ^(/${name})$ $1/ redirect;
      # '';
      # Homepage
      "gethomepage.dev/enabled" = "true";
      "gethomepage.dev/name" = "Keycloak";
      "gethomepage.dev/description" = "Identity management solution";
      "gethomepage.dev/group" = "Cluster Management";
      "gethomepage.dev/icon" = "keycloak.svg";
    };
    tls = true;
  };

  # httpRelativePath = ?;
}
