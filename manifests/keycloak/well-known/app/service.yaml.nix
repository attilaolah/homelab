{k, ...}:
k.api "Service" (let
  name = k.appname ./.;
  labels = import ./labels.nix;
in {
  metadata = {inherit name labels;};
  spec = {
    selector = labels;
    ports = [
      rec {
        inherit (k.defaults) protocol;
        name = "https";
        port = 8443;
        targetPort = port;
      }
    ];
  };
})
