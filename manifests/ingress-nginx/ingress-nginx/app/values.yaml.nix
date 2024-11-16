inputs @ {self, ...}: let
  namespace = "ingress-nginx";
  certificate = import ../config/certificate.yaml.nix inputs;
in {
  controller = {
    replicaCount = 2;
    ingressClassResource.default = true;
    service.annotations."lbipam.cilium.io/ips" = self.lib.cluster.network.external.ingress;
    extraArgs.default-ssl-certificate = "${namespace}/${certificate.spec.secretName}";
  };
}
