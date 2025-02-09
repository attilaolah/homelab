{k, ...}:
k.fluxcd.kustomization ./. {
  config.spec.dependsOn = map k.fluxcd.dep [./app];
}
