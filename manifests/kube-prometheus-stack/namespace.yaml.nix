{k, ...}:
k.namespace ./. {
  # Required by Node Exporter to access the host namespace.
  metadata.labels."pod-security.kubernetes.io/enforce" = "privileged";
}
