{
  lib,
  cluster,
  ...
}: let
  seed = toString 436606647;
in {
  # Server config.
  minecraftServer = {
    serverName = "Diesbach 2022";

    levelSeed = seed;
    levelName = "seed_${seed}";
    difficulty = "hard";

    defaultPermission = "visitor";
    ops = toString 2533274964742991; # Wintermuth
    members = lib.strings.concatStringsSep "," (map toString [
      2535412700806819 # UrsliBurgonya
      2535426640522603 # Elzza8077
      2535435227018955 # Noob3783
      2535440117113535 # Cservenak82
    ]);

    # Allow reaching the server from outside.
    serviceType = "LoadBalancer";

    eula = "TRUE";
  };

  # Request a slightly beefier node.
  resources.requests = {
    cpu = "2";
    memory = "4Gi";
  };
  nodeSelector."kubernetes.io/arch" = "amd64";

  # Persist data across pod restarts.
  persistence.dataDir = {
    enabled = true;
    size = "2Gi"; # 1Gi default
  };

  # Use a pre-defined IP for the service.
  # This allows NAT-ing the service, making it available on the internet.
  serviceAnnotations."lbipam.cilium.io/ips" = cluster.network.external.minecraft;
}
