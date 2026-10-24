{
  config,
  inputs,
  lib,
  pkgs,
  utils,
  ...
}: let
  # Reserved service address, outside the addresses assigned to individual hosts.
  vip = "192.168.1.43";

  hostName = config.networking.hostName;
  inventory = import (inputs.self + /inventory/data.nix);
  caddyPeers = {
    aria = {
      interface = "enp4s0";
      peer = "ilex";
    };
    ilex = {
      interface = "enp1s0";
      peer = "aria";
    };
  };
  peer = caddyPeers.${hostName};
  peerIp = inventory.machines.${peer.peer}.ip;
  isPrimary = hostName == "ilex";
in {
  # Allow the standby to open the floating-address listener before it owns the address.
  # This lets it accept traffic immediately when VRRP assigns it.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  networking.firewall = {
    allowedTCPPorts = [80];
    extraInputRules = ''
      iifname "${peer.interface}" ip saddr ${peerIp} ip protocol 112 accept
    '';
  };

  users = {
    groups.keepalived_script = {};
    users.keepalived_script = {
      isSystemUser = true;
      group = "keepalived_script";
      shell = "/run/current-system/sw/bin/nologin";
    };
  };

  services.caddy = {
    enable = true;

    # Do not leave Caddy's local admin endpoint listening alongside the VIP.
    globalConfig = "admin off";

    # An address with a port but no hostname is Caddy's HTTP catch-all site. `bind` still restricts its listener to the
    # floating address, rather than every local interface.
    virtualHosts."http://".extraConfig = ''
      bind ${vip}

      @dorn host dorn.haus
      handle @dorn {
        respond "OK" 200
      }

      handle {
        redir http://dorn.haus{uri} permanent
      }
    '';
  };

  systemd.services = {
    # Keepalived must not begin health tracking until Caddy has completed its systemd startup. `ip_nonlocal_bind` above
    # makes this valid on the standby.
    caddy = {
      before = ["keepalived.service"];
      requiredBy = ["keepalived.service"];
    };

    keepalived = {
      description = "Keepalived VRRP for the Caddy virtual IP";
      after = ["network-online.target" "caddy.service"];
      requires = ["caddy.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        RuntimeDirectory = "keepalived";
        RuntimeDirectoryMode = "0750";
        Environment = import (inputs.self + /modules/lib/systemd.nix) {inherit lib utils;} {
          CADDY_VRRP_HEALTH_CHECK = lib.getExe (pkgs.writeShellApplication {
            name = "caddy-vrrp-health";
            runtimeInputs = [pkgs.systemd];
            text = ''
              exec systemctl is-active --quiet caddy.service
            '';
          });
          HOST_IP = inventory.machines.${hostName}.ip;
          VRRP_PRIORITY =
            if isPrimary
            then 150
            else 100;
          VRRP_STATE =
            if isPrimary
            then "MASTER"
            else "BACKUP";
          VIRTUAL_IP = vip;
        };
        ExecStartPre = lib.getExe (pkgs.callPackage ./vrrp_config_gen.nix {});
        ExecStart = "${lib.getExe pkgs.keepalived} --dont-fork --use-file /run/keepalived/keepalived.conf";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
