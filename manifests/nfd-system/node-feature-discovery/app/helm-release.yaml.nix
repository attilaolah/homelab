{k, ...}:
k.fluxcd.helm-release ./. {
  spec.timeout = "20m";
}
