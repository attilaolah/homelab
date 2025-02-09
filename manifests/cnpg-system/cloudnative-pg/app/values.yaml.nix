# https://artifacthub.io/packages/helm/cloudnative-pg/cloudnative-pg#values
{
  monitoring = {
    podMonitorEnabled = true;
    grafanaDashboard.namespace = "observability";
  };
}
