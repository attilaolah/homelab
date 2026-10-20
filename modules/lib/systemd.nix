{
  lib,
  utils,
}:
lib.mapAttrsToList
(name: value: "${name}=${utils.escapeSystemdExecArg (toString value)}")
