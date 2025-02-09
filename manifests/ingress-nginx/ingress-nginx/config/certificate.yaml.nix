inputs @ {
  self,
  k,
  ...
}:
k.api "Certificate.cert-manager.io" (let
  inherit (issuer.metadata) name;
  inherit (self.lib.cluster) domain;

  issuer = import ../../../cert-manager/cert-manager/config/cluster-issuer.yaml.nix inputs;
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
