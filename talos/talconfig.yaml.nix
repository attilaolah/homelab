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
        machine.logging.destinations = [
          {
            endpoint = "udp://${cluster.network.external.vector}:6051/";
            format = "json_lines";
            extraTags.node = node.hostname;
          }
        ];
      }
    ];

    nodeLabels = {distro = "talos";} // optionalAttrs node.zfs {pvpool = "zfs";};
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
      cluster = {
        network = with cluster.network; {
          podSubnets = with pod; [cidr4 cidr6];
          serviceSubnets = with service; [cidr4 cidr6];
          cni.name = "none"; # we use cilium
        };
        # Use Cilium's KubeProxy replacement.
        proxy.disabled = true;
        controllerManager.extraArgs = {
          # Specify a higher IPv6 node CIDR mask.
          #
          # The node CIDR mask (obviously) must be larger than the subnet of the node IP CIDR configured for the kubelet.
          # For IPv4, the default pod subnet is a /16, and the default mask is 24, resulting in 24-16 = 8 bits of IPs for
          # nodes and another 32-24 = 8 bits assigned to each nodes. This allows 256 nodes with 256 IPs assigned to each
          # node.
          #
          # The IPv6 mask defaults to /64, so to still allow 256 nodes to get a /64, the node IP must be a /56. However,
          # Cilium won't accept such a large range, so the it is configured to use a /64 instead; to still allow for 8
          # bits worth of nodes, we set the mask to 64+8 = 72. This leaves 128-72 = 56 bits of address space per node.
          node-cidr-mask-size-ipv6 = 72;
        };
      };
      machine = {
        kubelet = {
          extraArgs.rotate-server-certificates = true;
          nodeIP.validSubnets = with cluster.network.node; [cidr4 cidr6];
        };
        network.nameservers = with cluster.network.uplink; dns4.two ++ dns6.one;
      };
    }
  ];
}
