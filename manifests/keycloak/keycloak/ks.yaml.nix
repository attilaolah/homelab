{k, ...}:
k.fluxcd.kustomization ./. {
  app.spec.dependsOn = map k.fluxcd.dep [./database];
  database.spec.dependsOn = map k.fluxcd.dep [
    ../../cnpg-system/cloudnative-pg/app
  ];
}
