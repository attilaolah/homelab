{cluster, ...}: {
  # Uses KubePrism on Talos nodes.
  # Uses an IPtables rule on Alpine nodes without KubePrism.
  k8sServiceHost = "127.0.0.1";
  k8sServicePort = 7445;
  kubeProxyReplacement = true;
  kubeProxyReplacementHealthzBindAddr = "0.0.0.0:10256";

  cgroup = {
    # Mount CGroup at a different location.
    # The default is to mount it at /run/cilium/cgroupv2.
    automount.enabled = false;
    hostRoot = "/sys/fs/cgroup";
  };

  # Enable use of per endpoint routes instead of routing via the cilium_host interface.
  endpointRoutes.enabled = true;

  # Disable Hubble.
  hubble.enabled = false;

  # Enable native routing.
  # This can be done because all nodes are on the same L2 network.
  routingMode = "native";
  autoDirectNodeRoutes = true;
  ipv4.enabled = true; # default
  ipv4NativeRoutingCIDR = cluster.network.node.cidr4;

  ipv6.enabled = true; # default = false
  # The Swisscom Router seems to advertise this address.
  # We should use something self-configured but this will do for now.
  ipv6NativeRoutingCIDR = cluster.network.node.cidr6;

  # Use L2 Announcements.
  l2announcements.enabled = true;
  externalIPs.enabled = true;

  # IPAM: Use cluster-scope (default).
  # Limit the pod CIDRs to avoid conflic with the node network.
  # The default pod CIDR is 10.0.0.0/8, which shadows the node network.
  ipam.operator = with cluster.network.pod; {
    clusterPoolIPv4MaskSize = 24; # default (cilium + kubernetes)
    clusterPoolIPv4PodCIDRList = cidr4; # default: ["10.0.0.0/8"]
    clusterPoolIPv6MaskSize = 64; # default: 120; kubernetes default: 64
    clusterPoolIPv6PodCIDRList = cidr6; # default: ["fd00::/104"]
  };

  loadBalancer.acceleration = "best-effort";

  # Enable local redirect policy.
  localRedirectPolicy = true;

  # Rollout pods automatically when a config map changes.
  rollOutCiliumPods = true;
  operator.rollOutPods = true;

  # Required security context capabilities.
  securityContext.capabilities = {
    ciliumAgent = [
      "CHOWN"
      "KILL"
      "NET_ADMIN"
      "NET_RAW"
      "IPC_LOCK"
      "SYS_ADMIN"
      "SYS_RESOURCE"
      "DAC_OVERRIDE"
      "FOWNER"
      "SETGID"
      "SETUID"
    ];
    cleanCiliumState = [
      "NET_ADMIN"
      "SYS_ADMIN"
      "SYS_RESOURCE"
    ];
  };
}
