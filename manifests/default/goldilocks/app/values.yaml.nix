{
  controller.resources = rec {
    limits = requests // {cpu = "200m";};
    requests = {
      cpu = "50m";
      memory = "256Mi";
      ephemeral-storage = "256Mi";
    };
  };
  dashboard.resources = rec {
    limits = requests // {cpu = "100m";};
    requests = {
      cpu = "50m";
      memory = "128Mi";
      ephemeral-storage = "128Mi";
    };
  };
}
