{
  cluster,
  k,
  ...
}: let
  inherit (cluster) domain;
in {
  hostname = k.hostname ./.;

  replicas = 2;
  restrictedAdmin = true;

  ingress = {
    extraAnnotations = {
      # TLS
      "cert-manager.io/cluster-issuer" = "letsencrypt";
      # Homepage
      "gethomepage.dev/enabled" = "true";
      "gethomepage.dev/name" = "Rancher";
      "gethomepage.dev/description" = "Cluster management interface";
      "gethomepage.dev/group" = "Cluster Management";
      "gethomepage.dev/icon" = "rancher.png";
      "gethomepage.dev/pod-selector" = "app=rancher";
    };
    # Rancher includes a cert-manager.io/issuer annotation by default.
    # We need to disable it so that we could use the cluster-issuer instead.
    includeDefaultExtraAnnotations = false;
    tls = {
      source = "secret";
      secretName = "${domain}-tls";
    };
  };
}
