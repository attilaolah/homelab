{k, ...}:
k.fluxcd.helm-release ./. {
  # Give Cilium more time to upgrade.
  # The "cilium" daemonset takes some time to fully roll out.
  spec.timeout = "28m";
}
