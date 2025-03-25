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

    revisionHistoryLimit = 2;
  };

  # Lower resource limits for workers.
  worker = let
    inherit (builtins) elemAt split;
    inherit (lib.strings) concatStringsSep escape;

    labels = [
      "cpu-model.vendor_id"
      "system-os_release.ID"
    ];
  in {
    core.labelWhitelist = "^(${escape ["."] (concatStringsSep "|" labels)})$";
    labelSources = map (label: elemAt (split "-" label) 0) labels;
    resources.limits = {
      cpu = "50m";
      memory = "128Mi";
    };
  };

  prometheus.enable = false; # todo
}
