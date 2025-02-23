{
  cluster,
  k,
  ...
}:
map (params: k.api "ClusterIssuer.cert-manager.io" params) [
  (let
    name = "internal-ca";
  in {
    metadata = {inherit name;};
    spec.ca.secretName = name;
  })
  (let
    prod = true;
    suffix =
      if prod
      then ""
      else "-staging";

    name = "letsencrypt";
    server = "https://acme${suffix}-v02.api.letsencrypt.org/directory";
  in {
    metadata = {inherit name;};
    spec.acme = {
      inherit server;

      email = with cluster; "${name}@${domain}";
      preferredChain = "";
      privateKeySecretRef = {inherit name;};
      solvers = [
        {
          dns01.cloudflare.apiTokenSecretRef = {
            name = "cloudflare-api-token";
            key = "api-token";
          };
          selector.dnsZones = [cluster.domain];
        }
      ];
    };
  })
]
