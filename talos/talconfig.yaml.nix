{
  lib,
  self,
  pkgs,
  ...
}: let
  inherit (builtins) elem head;
  inherit (lib.attrsets) optionalAttrs;
  inherit (lib.lists) flatten optional;
  inherit (self.lib) cluster yaml;

  node = node: {
    inherit (node) hostname controlPlane;

    ipAddress = node.ipv4;
    installDiskSelector.type = "ssd";
    networkInterfaces = [
      {
        deviceSelector.hardwareAddr = node.mac;
        addresses = with node; [net4 net6];
        routes = [
          {
            network = "0.0.0.0/0";
            gateway = cluster.network.uplink.gw4;
          }
          # IPv6 default route is auto-configured.
        ];
        dhcp = false;
      }
    ];

    kernelModules = optional node.zfs {name = "zfs";};

    schematic.customization.systemExtensions.officialExtensions = flatten [
      (optional (elem node.cpu ["intel" "amd"]) "siderolabs/${node.cpu}-ucode")
      (optional node.zfs "siderolabs/zfs")
    ];

    extraManifests = map (src: yaml.write src {inherit cluster pkgs;}) (flatten [
      (optional node.watchdog ./manifests/watchdog.yaml.nix)
      ./manifests/vector.yaml.nix
    ]);

    patches = map yaml.format [
      {
        machine = {
          # Disable DNS forwarding, for two reasons:
          # 1. Configuring it on Alpine nodes requires a non-trivial amount of effort.
          # 2. It clashes with Cilium's eBPF-based masquerading: https://github.com/siderolabs/talos/issues/8836
          features.hostDNS.forwardKubeDNSToHost = false;
          # Elasticsearch minimum requirements.
          # https://www.elastic.co/guide/en/elasticsearch/reference/8.17/bootstrap-checks-max-map-count.html
          sysctls."vm.max_map_count" = "262144";
          # Redirect logs to Vector.
          logging.destinations = [
            {
              endpoint = "udp://${cluster.network.external.vector}:6051/";
              format = "json_lines";
              extraTags.node = node.hostname;
            }
          ];
        };
      }
    ];

    nodeLabels =
      {"feature.node.kubernetes.io/system-os_release.ID" = "talos";}
      // optionalAttrs node.zfs {pvpool = "zfs";};
  };
in {
  clusterName = cluster.name;
  talosVersion = cluster.versions.talos.github-releases;
  kubernetesVersion = cluster.versions.kubernetes.github-releases;
  endpoint = "https://${(head cluster.nodes.by.controlPlane).ipv4}:6443";

  # Allow running jobs on control plane nodes.
  # Currently the control plane nodes don't do much anyway.
  allowSchedulingOnControlPlanes = true;

  nodes = map node cluster.nodes.by.os.talos;

  patches = map yaml.format [
    {
      cluster = let
        scheduler.extraArgs."bind-address" = "0.0.0.0";
      in {
        inherit scheduler;
        controllerManager = scheduler;
        apiServer.extraArgs = {
          # Enable OIDC authentication against the Kubernetes API server.
          # Headlamp will forward the user's email address (see claim below) as the principal.
          oidc-client-id = "kubernetes";
          # This endpoint won't be available until Keycloak is up and running, but that's fine.
          # Once Keycloak and Headlamp are up and running, this will allow credential forwarding.
          oidc-issuer-url = "https://${cluster.domain}/keycloak/realms/dh";
          oidc-username-claim = "email";
        };
        network = with cluster.network; {
          podSubnets = with pod; [cidr4 cidr6];
          serviceSubnets = with service; [cidr4 cidr6];
          cni.name = "none"; # we use cilium
        };
        # Use Cilium's KubeProxy replacement.
        proxy.disabled = true;
      };
      machine = {
        kubelet = {
          extraArgs.rotate-server-certificates = true;
          extraConfig.serverTLSBootstrap = true;
          nodeIP.validSubnets = with cluster.network.node; [cidr4 cidr6];
        };
        network.nameservers = with cluster.network.uplink; dns4.two ++ dns6.one;
      };
    }
  ];
}
