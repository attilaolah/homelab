{self, ...}: {
  service = {
    # Expose the service externally.
    # Needed for Talos & Alpine logs forwarding.
    type = "LoadBalancer";
    annotations."lbipam.cilium.io/ips" = self.lib.cluster.network.external.vector;
  };

  autoscaling = {
    enabled = true;
    maxReplicas = 2;
  };

  customConfig = {
    api = {
      enabled = true;
      address = "127.0.0.1:8686";
      playground = false;
    };

    sources = let
      talos = port: {
        address = "0.0.0.0:${toString port}";
        type = "socket";
        mode = "udp";
        max_length = 1024 * 100;
        decoding.codec = "json";
        host_key = "__host";
      };
    in {
      talos_kernel_logs = talos 6050;
      talos_services_logs = talos 6051;
    };

    sinks = let
      loki = "http://loki:3100";
      talos = src: batch: labels: {
        type = "loki";
        inputs = ["talos_${src}_logs"];
        endpoint = loki;
        encoding = {
          codec = "json";
          except_fields = ["__host"];
        };
        batch.max_bytes = batch * 1024;
        out_of_order_action = "rewrite_timestamp";
        labels =
          {
            level = "{{`{{ talos-level }}`}}";
            node_ip = "{{`{{ __host }}`}}";
          }
          // labels;
      };
    in {
      talos_kernel = talos "kernel" 1024 {};
      talos_services = talos "services" 256 {
        node = "{{`{{ node }}`}}";
      };
    };
  };
}
