args @ {k, ...}:
k.api "NetworkPolicy.networking.k8s.io" (let
  name = k.appname ./.;
  values = import ./values.nix args;
  # ) labels selector;
in {
  metadata = {
    inherit name;
    inherit (values) labels;
  };
  spec = {
    podSelector.matchLabels = values.selector;
    policyTypes = ["Ingress" "Egress"];

    # Egress Rules: Deny all outgoing traffic.
    egress = [];

    # Ingress Rules: Allow incoming traffic only from specific sources.
    ingress = [
      {
        from = [
          {
            namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "observability";
            podSelector.matchExpressions = [
              {
                key = "app.kubernetes.io/name";
                operator = "In";
                values = ["alertmanager" "prometheus"];
              }
            ];
          }
          {
            namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "observability";
            podSelector.matchLabels = k.annotations.group "app.kubernetes.io" {
              name = "jaeger";
              component = "query";
            };
          }
        ];
      }
    ];
  };
})
