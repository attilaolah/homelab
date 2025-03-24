{
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
  worker.resources.limits = {
    cpu = "50m";
    memory = "128Mi";
  };

  prometheus.enable = false; # todo
}
