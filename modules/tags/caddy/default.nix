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
  isPrimary = hostName == "ilex";
in {
  # Allow the standby to open the floating-address listener before it owns the
  # address.  This lets it accept traffic immediately when VRRP assigns it.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  networking.firewall.allowedTCPPorts = [80];

  services.caddy = {
    enable = true;

    # Do not leave Caddy's local admin endpoint listening alongside the VIP.
    globalConfig = "admin off";

    # An explicit HTTP address prevents automatic HTTPS and binds the public
    # listener to the floating address rather than every local interface.
    virtualHosts."http://${vip}".extraConfig = ''
      respond "Caddy is not configured yet" 200
    '';
  };

  systemd.services = {
    # Keepalived must not begin health tracking until Caddy has completed its
    # systemd startup.  ip_nonlocal_bind above makes this valid on the standby.
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
          HOST_IP = (import (inputs.self + /inventory/data.nix)).machines.${hostName}.ip;
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
