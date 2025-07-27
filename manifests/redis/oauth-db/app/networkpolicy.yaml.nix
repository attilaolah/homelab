args @ {k, ...}:
k.api "NetworkPolicy.networking.k8s.io" (let
  name = k.appname ./.;
  values = import ./values.nix args;
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
        from =
          map (podSelector: {
            inherit podSelector;
            namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "observability";
          }) [
            {
              matchExpressions = [
                {
                  key = "app.kubernetes.io/name";
                  operator = "In";
                  values = ["alertmanager" "prometheus"];
                }
              ];
            }
            {
              matchLabels = k.annotations.group "app.kubernetes.io" {
                name = "jaeger";
                component = "query";
              };
            }
          ];
      }
    ];
  };
})
