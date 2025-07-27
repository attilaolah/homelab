args @ {k, ...}:
k.api "Service" (let
  name = k.fluxcd.ksname ./.;
  values = import ./values.nix args;
in {
  metadata = {
    inherit name;
    inherit (values) labels;
  };
  spec = {
    inherit (values) selector;
    ports = [
      (let
        name = values.protocol;
      in {
        inherit name;
        inherit (values) port;
        inherit (k.defaults) protocol;
        targetPort = name;
        appProtocol = name;
      })
    ];
  };
})
