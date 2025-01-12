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
        addresses = [node.net4];
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

    extraManifests = map (src: yaml.write src {inherit pkgs;}) [
      ./manifests/vector.yaml.nix
      ./manifests/watchdog.yaml.nix
    ];

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
