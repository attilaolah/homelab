{...}: let
  # Reserved service address, outside the addresses assigned to individual hosts.
  virtualIp = "192.168.4.43";
in {
  # Allow the standby to open the floating-address listener before it owns the
  # address.  This lets it accept traffic immediately when VRRP assigns it.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  services.caddy = {
    enable = true;

    # Do not leave Caddy's local admin endpoint listening alongside the VIP.
    globalConfig = "admin off";

    # An explicit HTTP address prevents automatic HTTPS and binds the public
    # listener to the floating address rather than every local interface.
    virtualHosts."http://${virtualIp}".extraConfig = ''
      respond "Caddy is not configured yet" 200
    '';
  };

  # Keepalived must not begin health tracking until Caddy has completed its
  # systemd startup.  ip_nonlocal_bind above makes this valid on the standby.
  systemd.services.caddy = {
    before = ["keepalived.service"];
    requiredBy = ["keepalived.service"];
  };
}
