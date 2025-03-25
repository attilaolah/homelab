{k, ...}:
k.fluxcd.helm-release ./. {
  spec.timeout = "40m";
}
