# https://github.com/kubernetes-sigs/node-feature-discovery/blob/master/deployment/helm/node-feature-discovery/values.yaml
{lib, ...}: {
  master = {
    # TODO: Add a second replica.
    # The master deployment has pod affinity that assigns it to control plane nodes.
    # Since we currently run with a single contrel plane nodes, that means they both end up on the same node.
    replicaCount = 1;

    resources.limits = {
      cpu = "400m";
      memory = "1Gi";
    };
  };

  worker = let
    inherit (builtins) elemAt split;
    inherit (lib.strings) concatStringsSep escape;

    labels = [
      "cpu-model.vendor_id"
      "system-os_release.ID"
    ];
  in {
    config.core = {
      labelSources = map (label: elemAt (split "-" label) 0) labels;
      labelWhitelist = "^(${escape ["."] (concatStringsSep "|" labels)})$";
    };

    # Lower resource limits for workers.
    resources = {
      requests = {
        cpu = "5m"; # default
        memory = "64Mi"; # default
        ephemeral-storage = "64Mi";
      };
      limits = {
        cpu = "200m";
        memory = "128Mi"; # default: 512Mi
        ephemeral-storage = "256Mi";
      };
    };
  };

  prometheus.enable = false; # todo
}
