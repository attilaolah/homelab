{k, ...}:
k.fluxcd.kustomization ./. {
  app.spec.dependsOn = map k.fluxcd.dep [
    ../../cert-manager/cert-manager/app
  ];
  config.spec.dependsOn = map k.fluxcd.dep [./app];
}
