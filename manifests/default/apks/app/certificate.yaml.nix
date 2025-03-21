{k, ...}:
k.api "Certificate.cert-manager.io" (let
  name = k.appname ./.;
  labels = import ./labels.nix;
in {
  metadata = {inherit name labels;};
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
