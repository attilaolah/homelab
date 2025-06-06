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
  resources = {
    limits = {
      cpu = "4";
      memory = "6Gi";
      ephemeral-storage = "64Gi";
    };
    requests = {
      cpu = "2";
      memory = "4Gi";
      ephemeral-storage = "16Gi";
    };
  };
  nodeSelector = {
    "kubernetes.io/arch" = "amd64";
    "feature.node.kubernetes.io/cpu-model.vendor_id" = "Intel";
  };

  # Persist data across pod restarts.
  persistence.dataDir = {
    enabled = true;
    size = "2Gi"; # 1Gi default
  };

  # Use a pre-defined IP for the service.
  # This allows NAT-ing the service, making it available to the public.
  serviceAnnotations."lbipam.cilium.io/ips" = cluster.network.external.minecraft;
}
