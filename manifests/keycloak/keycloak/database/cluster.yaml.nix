{k, ...}:
k.api "Cluster.postgresql.cnpg.io" {
  metadata.name = k.fluxcd.ksname ./.;
  spec = {
    instances = 2;
    storage.size = "2Gi";
    bootstrap.initdb.database = k.appname ./.;

    monitoring.enablePodMonitor = true;
  };
}
