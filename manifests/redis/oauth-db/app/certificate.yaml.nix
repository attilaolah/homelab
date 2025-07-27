args @ {k, ...}:
k.api "Certificate.cert-manager.io" (let
  name = k.appname ./.;
  inherit (import ./values.nix args) labels;
in {
  metadata = {inherit name labels;};
  spec = {
    secretName = "${name}-tls";
    issuerRef = {
      kind = "ClusterIssuer";
      name = "internal-ca";
    };
    commonName = name;
    dnsNames = [
      # Used by OAuth2 Proxy instances:
      "${name}.${k.nsname ./.}.svc"
      # Used by redis-cli probes:
      "localhost"
    ];
  };
})
