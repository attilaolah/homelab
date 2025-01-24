# Kubernetes API part of the k0s version.
{
  lib,
  v,
  ...
}: let
  inherit (builtins) elemAt head;
  inherit (lib.strings) removePrefix splitString;
  parts = splitString "." (head (splitString "+" (removePrefix "v" v.k0s.github-releases)));
in "${elemAt parts 0}.${elemAt parts 1}"
