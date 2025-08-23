{k, ...}:
k.fluxcd.helm-release ./. {
  spec.upgrade.timeout = "20m";
}
