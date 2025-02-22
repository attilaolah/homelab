{k, ...}:
k.fluxcd.kustomization ./. rec {
  app.spec = {
    prune = false;
    timeout = "30m";
  };
  config.spec = {
    inherit (app.spec) prune;
    dependsOn = map k.fluxcd.dep [./app];
  };
}
