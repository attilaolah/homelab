{k, ...}:
k.api "Certificate.cert-manager.io" (let
  name = "jaeger-query";
in {
  metadata = {inherit name;};
  spec = {
    secretName = "${name}-tls";
    issuerRef = {
      kind = "ClusterIssuer";
      name = "internal-ca";
    };
    commonName = name;
    dnsNames = [name];
  };
})
