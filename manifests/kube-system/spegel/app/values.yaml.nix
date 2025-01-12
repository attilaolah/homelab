{
  affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
    {
      matchExpressions = [
        {
          key = "distro";
          operator = "NotIn";
          values = ["alpine"];
        }
      ];
    }
  ];
  spegel.containerdRegistryConfigPath = "/etc/cri/conf.d/hosts";
  revisionHistoryLimit = 4;
}
