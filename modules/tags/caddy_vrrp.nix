{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  machineData = import (inputs.self + /inventory/data.nix);
  hostName = config.networking.hostName;
  isPrimary = hostName == "ilex";
  hostIp = machineData.machines.${hostName}.ip;
  virtualIp = "192.168.4.43";
  caddyHealthCheck = pkgs.writeShellApplication {
    name = "caddy-vrrp-health";
    runtimeInputs = [pkgs.systemd];
    text = ''
      exec systemctl is-active --quiet caddy.service
    '';
  };
    keepalivedConfig = pkgs.writeShellApplication {
      name = "write-caddy-vrrp-config";
      runtimeInputs = [pkgs.gawk pkgs.iproute2];
      text = builtins.readFile ./write_caddy_vrrp_config.sh;
  };
in {
  systemd.services.keepalived = {
    description = "Keepalived VRRP for the Caddy virtual IP";
    after = ["network-online.target" "caddy.service"];
    requires = ["caddy.service"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "simple";
        RuntimeDirectory = "keepalived";
        RuntimeDirectoryMode = "0750";
        Environment = [
          "CADDY_VRRP_HEALTH_CHECK=${lib.getExe caddyHealthCheck}"
          "HOST_IP=${hostIp}"
          "VRRP_PRIORITY=${if isPrimary then "150" else "100"}"
          "VRRP_STATE=${if isPrimary then "MASTER" else "BACKUP"}"
          "VIRTUAL_IP=${virtualIp}"
        ];
        ExecStartPre = lib.getExe keepalivedConfig;
        ExecStart = "${lib.getExe pkgs.keepalived} --dont-fork --config /run/keepalived/keepalived.conf";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
