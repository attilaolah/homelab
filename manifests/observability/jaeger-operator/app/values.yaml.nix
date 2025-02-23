# https://artifacthub.io/packages/helm/jaegertracing/jaeger-operator#configuration
{
  # Simple all-in-one configuration.
  # allInOne.enabled = true;
  # agent.enabled = false;
  # collector.enabled = false;
  # query.enabled = false;
  # provisionDataStore.cassandra = false;
  # storage.type = "memory";
  # jaeger:
  #   # Create a Jaeger instance.
  #   create: true
  #   spec:
  #     strategy: allInOne
  #     storage:
  #       type: memory
  #       options:
  #         memory:
  #           max-traces: 1000
  #     ingress:
  #       enabled: true
  #       annotations:
  #         kubernetes.io/ingress.class: nginx
  #       hosts:
  #       - jaeger.net-kub-test-1.nmag.ch
  #       security: none
  #
  #
  # Ue a ClusterRole to allow listing ingress classes.
  rbac.clusterRole = true;
}
