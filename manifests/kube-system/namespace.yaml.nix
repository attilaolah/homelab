{k, ...}:
k.namespace ./. {
  metadata.labels."kustomize.toolkit.fluxcd.io/prune" = "disabled";
}
