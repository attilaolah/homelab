let
  component = {
    resources = {
      requests = {
        cpu = "25m";
        memory = "256Mi";
      };
      limits = {
        cpu = "100m";
        memory = "1Gi";
      };
    };
  };
in {
  controller = component;
  dashboard = component;
}
