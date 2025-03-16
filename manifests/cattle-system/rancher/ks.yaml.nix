{k, ...}:
k.fluxcd.kustomization ./. {
  # TODO: Latest Kubernetes version is not supported.
  spec.suspend = true;
}
