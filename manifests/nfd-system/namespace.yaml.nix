{k, ...}:
k.namespace ./. {
  metadata.labels."pod-security.kubernetes.io/enforce" = "privileged";
}
