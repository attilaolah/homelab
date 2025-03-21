{
  cluster,
  k,
  ...
}:
k.api "Ingress.networking.k8s.io" (let
  inherit (cluster) domain;
  name = k.appname ./.;
  namespace = k.nsname ./.;
  labels = import ./labels.nix;
in {
  metadata = {
    inherit name labels;

    annotations = {
      # TLS
      "cert-manager.io/cluster-issuer" = "letsencrypt";
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS";
      "nginx.ingress.kubernetes.io/proxy-ssl-name" = name;
      "nginx.ingress.kubernetes.io/proxy-ssl-secret" = "${namespace}/${name}-tls";
      # Homepage
      "gethomepage.dev/enabled" = "true";
      "gethomepage.dev/name" = "APKs";
      "gethomepage.dev/description" = "Alpine APK mirrer containing k0s";
      "gethomepage.dev/group" = "Misc.";
      "gethomepage.dev/icon" = "si-alpinelinux.svg";
    };
  };
  spec = {
    ingressClassName = "nginx";
    rules = [
      {
        host = domain;
        http.paths = [
          {
            path = "/${name}/";
            pathType = "ImplementationSpecific";
            backend.service = {
              inherit name;
              port.name = "https";
            };
          }
        ];
      }
    ];
  };
})
