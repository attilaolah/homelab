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

    annotations = with k.annotations;
      cert-manager
      // (ingress-nginx {
        inherit name namespace;
        secret = "${name}-tls";
      })
      // (homepage {
        name = "APKs";
        description = "Alpine APK mirrer containing k0s";
        icon = "alpine-linux";
        group = "Cluster Management";
      });
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
    tls = [
      {
        hosts = [domain];
        secretName = "${domain}-tls";
      }
    ];
  };
})
