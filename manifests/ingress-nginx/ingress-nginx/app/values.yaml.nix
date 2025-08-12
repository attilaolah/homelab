# https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx#values
# https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml
inputs @ {
  cluster,
  lib,
  ...
}: let
  inherit (lib.strings) concatStringsSep;
  namespace = "ingress-nginx";
  certificate = import ../config/certificate.yaml.nix inputs;
in {
  controller = {
    replicaCount = 2;
    ingressClassResource.default = true;
    service.annotations."lbipam.cilium.io/ips" = cluster.network.external.ingress;
    extraArgs.default-ssl-certificate = "${namespace}/${certificate.spec.secretName}";

    addHeaders = {
      # TODO: Specify fine-grained per-app policies.
      #"content-security-policy" = concatStringsSep "; " [
      #  "default-src 'self'"
      #  # Homepage service icons are served from jsdelivr.
      #  "img-src 'self' https://cdn.jsdelivr.net"
      #  # Headlamp requires unsafe-eval, Alertmanager, Prometheus & Homepage require unsafe-inline.
      #  "script-src 'self' 'unsafe-inline' 'unsafe-eval'"
      #  "style-src 'self' 'unsafe-inline'"
      #  "form-action 'self'"
      #  "frame-ancestors 'self'"
      #  "object-src 'none'"
      #];
      "x-content-type-options" = "nosniff";
    };
    config.hide-headers = concatStringsSep "," [
      # NextJS (Homepage) headers:
      "x-nextjs-cache"
      "x-powered-by"
      # Old XSS protection headers:
      "x-xss-protection"
    ];
  };
}
