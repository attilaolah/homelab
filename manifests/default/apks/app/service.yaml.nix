{k, ...}:
k.api "Service" (let
  name = k.appname ./.;
  labels = import ./labels.nix;
in {
  metadata = {inherit name labels;};
  spec = {
    type = "ClusterIP";
    selector = labels;
    ports = [
      {
        name = "https";
        port = 443;
        targetPort = 8443;
      }
    ];
  };
})
