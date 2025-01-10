let
  # TODO: Renovate!
  k0s = "1.31.3-k0s.0";
in {
  inherit k0s;

  # TODO: Renovate!
  pause = "3.9";

  # Kubernetes API part of the k0s version.
  k8sapi = {lib, ...}: let
    inherit (builtins) elemAt head;
    inherit (lib.strings) splitString;
    parts = splitString "." (head (splitString "-" k0s));
  in "${elemAt parts 0}.${elemAt parts 1}";
}
