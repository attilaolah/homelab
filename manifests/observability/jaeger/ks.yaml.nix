{k, ...}:
k.fluxcd.kustomization ./. {
  app.spec.dependsOn = map k.fluxcd.dep [
    ../../kube-system/external-secrets/app
    ../../cert-manager/cert-manager/app
  ];
}
