inputs @ {
  self,
  k,
  v,
  ...
}:
k.api "ConfigMap" (let
  inherit (builtins) baseNameOf dirOf mapAttrs replaceStrings toJSON;
  inherit (self.lib) cluster;

  name = baseNameOf (dirOf ./.);
  k8sapi = (import ./k8sapi.nix) inputs;
  version = replaceStrings ["+"] ["-"] v.k0s.github-releases;
in {
  metadata = {
    name = "worker-config-alpine-${k8sapi}";
    labels = {
      "app.kubernetes.io/name" = name;
      "app.kubernetes.io/version" = version;
      "app.kubernetes.io/component" = "worker-config";
      "k0s.k0sproject.io/worker-profile" = "alpine";
      "k0s.k0sproject.io/stack" = "${name}-worker-config-${k8sapi}";
    };
  };
  data = mapAttrs (name: spec: toJSON spec) {
    # TODO: Use the IPv6 address to talk to the API server.
    apiServerAddresses = map ({ipv4, ...}: "${ipv4}:6443") cluster.nodes.by.controlPlane;
    konnectivity = {
      enabled = false;
      agentPort = 8132; # unused but required
    };
    nodeLocalLoadBalancing.enabled = false;
    pauseImage = {
      image = "registry.k8s.io/pause";
      version = v.pause.docker;
    };
    kubeletConfiguration = k.api "KubeletConfiguration.kubelet.config.k8s.io" {
      syncFrequency = "0s";
      fileCheckFrequency = "0s";
      httpCheckFrequency = "0s";
      tlsCipherSuites = [
        # TLS 1.3 cipher suites (enabled by default):
        "TLS_AES_128_GCM_SHA256"
        "TLS_AES_256_GCM_SHA384"
        "TLS_CHACHA20_POLY1305_SHA256"
      ];
      tlsMinVersion = "VersionTLS13";
      rotateCertificates = true;
      serverTLSBootstrap = true;
      authentication = {
        x509 = {};
        webhook = {
          enabled = true;
          cacheTTL = "0s";
        };
        anonymous.enabled = false;
      };
      authorization = {
        mode = "Webhook";
        webhook = {
          cacheAuthorizedTTL = "0s";
          cacheUnauthorizedTTL = "0s";
        };
      };
      eventRecordQPS = 0;
      clusterDomain = "cluster.local";
      clusterDNS = ["10.96.0.10" "fd10:96::a"];
      streamingConnectionIdleTimeout = "0s";
      nodeStatusUpdateFrequency = "0s";
      nodeStatusReportFrequency = "0s";
      imageMinimumGCAge = "0s";
      imageMaximumGCAge = "0s";
      volumeStatsAggPeriod = "0s";
      cgroupsPerQOS = true;
      cpuManagerReconcilePeriod = "0s";
      runtimeRequestTimeout = "0s";
      evictionPressureTransitionPeriod = "0s";
      failSwapOn = false; # small machines have swap
      systemReserved = {
        cpu = "50m";
        memory = "512Mi";
        ephemeral-storage = "256Mi";
        pid = "100";
      };
      memorySwap = {};
      oomScoreAdj = -450;
      port = 10250;
      protectKernelDefaults = true;
      resolvConf = "/system/resolved/resolv.conf";
      logging = {
        flushFrequency = 0;
        verbosity = 0;
        options = let
          default = {infoBufferSize = "0";};
        in {
          text = default;
          json = default;
        };
      };
      seccompDefault = true;
      serializeImagePulls = false;
      shutdownGracePeriod = "30s";
      shutdownGracePeriodCriticalPods = "10s";
      containerRuntimeEndpoint = "";
    };
  };
})
