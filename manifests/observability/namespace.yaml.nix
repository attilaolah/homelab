{k, ...}:
k.namespace ./. {
  metadata.labels = {
    "goldilocks.fairwinds.com/enabled" = "true";
    # Required by Node Exporter to access the host namespace.
    "pod-security.kubernetes.io/enforce" = "privileged";
  };
}
