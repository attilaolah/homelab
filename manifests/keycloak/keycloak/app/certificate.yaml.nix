{
  cluster,
  k,
  ...
}:
k.api "Certificate.cert-manager.io" (let
  name = k.appname ./.;
in {
  metadata = {inherit name;};
  spec = {
    secretName = "${name}-tls";
    issuerRef = {
      kind = "ClusterIssuer";
      name = "internal-ca";
    };
    commonName = name;
    dnsNames = [cluster.domain];
  };
})
