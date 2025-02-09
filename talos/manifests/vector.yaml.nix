{cluster, ...}: {
  kind = "KmsgLogConfig";
  apiVersion = "v1alpha1";
  name = "vector-logs";
  url = "udp://${cluster.network.external.vector}:6050/";
}
