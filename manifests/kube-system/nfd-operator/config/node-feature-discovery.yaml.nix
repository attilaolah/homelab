{
  k,
  self,
  ...
}:
k.api "NodeFeatureDiscovery.nfd.kubernetes.io" {
  metadata.name = "network-device";
  spec.workerConfig.configData = self.lib.yaml.format {
    sources.custom = [
      {
        feature = "network.device";
        matchExpressions = {
          operstate = {
            op = "In";
            value = ["up"];
          };
          speed = {
            op = "Gt";
            value = ["100"];
          };
        };
      }
    ];
  };
}
