{self, ...}: let
  inherit (builtins) baseNameOf dirOf mapAttrs toJSON;
  inherit (self.lib) cluster;

  name = baseNameOf (dirOf ./.);
  # TODO: Renovate!
  version = "1.31.3-k0s.0";
  majorMinor = "1.31"; # TODO
in {
  kind = "ConfigMap";
  apiVersion = "v1";
  metadata = {
    name = "worker-config-alpine-${majorMinor}";
    labels = {
      "app.kubernetes.io/name" = name;
      "app.kubernetes.io/component" = "worker-config";
      "app.kubernetes.io/version" = "v${version}";
      "k0s.k0sproject.io/stack" = "${name}-worker-config-${majorMinor}";
      "k0s.k0sproject.io/worker-profile" = "alpine";
    };
  };
  data = mapAttrs (name: spec: toJSON spec) {
    apiServerAddresses = map ({ipv4, ...}: "https://${ipv4}:6443") cluster.nodes.by.controlPlane;
    konnectivity.enabled = false;
    nodeLocalLoadBalancing.enabled = false;
    pauseImage = {
      image = "registry.k8s.io/pause";
      # TODO: Renovate!
      version = "3.9";
    };
    kubeletConfiguration = {
      kind = "KubeletConfiguration";
      apiVersion = "kubelet.config.k8s.io/v1beta1";
      syncFrequency = "0s";
      fileCheckFrequency = "0s";
      httpCheckFrequency = "0s";
      tlsCipherSuites = [
        # TODO: Do we really need all these?
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
      ];
      # TODO: 1.3?
      tlsMinVersion = "VersionTLS12";
      rotateCertificates = true;
      serverTLSBootstrap = true;
      authentication = {
        x509 = {};
        webhook.cacheTTL = "0s";
        anonymous = {};
      };
      authorization.webhook = {
        cacheAuthorizedTTL = "0s";
        cacheUnauthorizedTTL = "0s";
      };
      eventRecordQPS = 0;
      clusterDomain = cluster.domain;
      # TODO: Is this stable?
      clusterDNS = ["10.96.0.10"];
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
      failSwapOn = false;
      memorySwap = {};
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
      shutdownGracePeriod = "0s";
      shutdownGracePeriodCriticalPods = "0s";
      containerRuntimeEndpoint = "";
    };
  };
}
