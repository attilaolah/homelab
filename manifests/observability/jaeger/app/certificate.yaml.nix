{k, ...}:
map (
  component:
    k.api "Certificate.cert-manager.io" (let
      name = "jaeger-${component}";
    in {
      metadata = {inherit name;};
      spec = {
        secretName = "${name}-tls";
        issuerRef = {
          kind = "ClusterIssuer";
          name = "internal-ca";
        };
        commonName = name;
        dnsNames = [
          name
          "jaeger" # for tls query without oauth
          "localhost" # for oauth sidecar
        ];
      };
    })
) ["query" "collector"]
