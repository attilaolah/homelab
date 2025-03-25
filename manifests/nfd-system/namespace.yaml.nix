{k, ...}:
k.namespace ./. {
  metadata.labels = {
    "goldilocks.fairwinds.com/enabled" = "true";
    "pod-security.kubernetes.io/enforce" = "privileged";
  };
}
