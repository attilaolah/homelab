let
  component = {
    replicaCount = 2;
    podDisruptionBudget = {
      enabled = true;
      minAvailable = 1;
    };

    resources = {
      requests = {
        cpu = "50m";
        memory = "512Mi";
      };
      limits = {
        cpu = "200m";
        memory = "2Gi";
      };
    };
  };
in {
  recommender = component;
  updater = component;
  admissionController =
    component
    // {
      resources = {
        requests = {
          cpu = "50m";
          memory = "256Mi";
        };
        limits = {
          cpu = "200m";
          memory = "1Gi";
        };
      };
    };
}
