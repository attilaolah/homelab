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
        name = "https";
        protocol = "TCP";
        port = 8443;
        targetPort = port;
      }
    ];
  };
})
