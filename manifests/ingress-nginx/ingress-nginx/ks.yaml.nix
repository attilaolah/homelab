{k, ...}:
k.fluxcd.kustomization ./. {
  config.spec.dependsOn = map k.fluxcd.dep [
    ../../cert-manager/cert-manager/config
  ];
}
