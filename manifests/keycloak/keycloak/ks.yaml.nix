{k, ...}:
k.fluxcd.kustomization ./. {
  app.spec = {
    dependsOn = map k.fluxcd.dep [./database];
    timeout = "20m";
  };
  database.spec.dependsOn = map k.fluxcd.dep [
    ../../cnpg-system/cloudnative-pg/app
  ];
}
