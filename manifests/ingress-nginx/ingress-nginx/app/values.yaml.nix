# https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx#values
# https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml
inputs @ {cluster, ...}: let
  namespace = "ingress-nginx";
  certificate = import ../config/certificate.yaml.nix inputs;
in {
  controller = {
    replicaCount = 2;
    ingressClassResource.default = true;
    service.annotations."lbipam.cilium.io/ips" = cluster.network.external.ingress;
    extraArgs.default-ssl-certificate = "${namespace}/${certificate.spec.secretName}";

    # Add & remove headers:
    addHeaders."Content-Security-Policy" = "frame-ancestors 'self'";
    config.hide-headers = "X-Powered-By";
  };
}
