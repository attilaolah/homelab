# https://artifacthub.io/packages/helm/jaegertracing/jaeger-operator#configuration
{
  jaeger = {
    # Create a Jaeger instance.
    create = true;
    spec = {
      strategy = "allInOne";
      storage = {
        type = "memory";
        options.memory.max-traces = 1000;
      };
      ingress.enabled = false;
    };
  };

  # Ue a ClusterRole to allow listing ingress classes.
  rbac.clusterRole = true;
}
