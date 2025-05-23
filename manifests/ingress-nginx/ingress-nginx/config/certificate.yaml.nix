{
  cluster,
  k,
  ...
}:
k.api "Certificate.cert-manager.io" (let
  inherit (cluster) domain;

  name = "letsencrypt";
in {
  metadata = {inherit name;};
  spec = {
    secretName = "${name}-tls";
    issuerRef = {
      inherit name;
      kind = "ClusterIssuer";
    };
    commonName = domain;
    dnsNames = [domain];
  };
})
