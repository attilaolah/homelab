{
  loki = rec {
    auth_enabled = false;
    commonConfig.replication_factor = 1;
    schemaConfig.configs = [
      {
        from = "2024-01-01";
        object_store = storage.type;
        store = "tsdb";
        schema = "v13";
        index = {
          prefix = "loki_index_";
          period = "24h";
        };
      }
    ];
    storage.type = "filesystem";
  };

  deploymentMode = "SingleBinary";
  singleBinary = {
    replicas = 1;
    persistence.size = "20Gi"; # 10Gi default
  };

  read.replicas = 0;
  write.replicas = 0;
  backend.replicas = 0;
  chunksCache.enabled = false;

  monitoring = {
    dashboards.enabled = true;
    serviceMonitor = {
      enabled = true;
      metricsInstance.enabled = true;
    };
  };

  # Allow ingesting logs from outside the cluster (e.g. Alpine hosts).
  gateway.service.type = "LoadBalancer";
}
