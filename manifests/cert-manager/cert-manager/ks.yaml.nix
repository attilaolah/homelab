{k, ...}:
k.fluxcd.kustomization ./. {
  config.spec.dependsOn = map k.fluxcd.dep [
    ../../kube-system/external-secrets/app
    ./app
  ];
}
