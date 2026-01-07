{self}: let
  inherit (self.lib) cidr;

  # IPv4 subnet enforced by the router.
  # Using any other subnet would work for local comms but not for internet connectivity.
  local = c: d: "192.168.${toString c}.${toString d}";
in {
  node = rec {
    net4 = local 1 0;
    net4Len = 24;
    cidr4 = cidr net4 net4Len;

    # L2 natively routable addresses.
    # DHCP advertises a /24, however, the entire /16 should still be routable locally.
    net4LenRoutable = 16;
    routableCIDR4 = cidr (local 0 0) net4LenRoutable;

    # IPv4 node range: 192.168.1.100-254.
    # Sunrise's ConnectBox 3 apparently won't let us configure DHCP with a /16 block.
    offset = 100;

    # GUA prefix set by the modem:
    net6 = "2001:1708:2601:d900::";
    net6Len = 64;
    cidr6 = cidr net6 net6Len;
  };

  pod = rec {
    net4 = "10.244.0.0";
    net4Len = 16;
    cidr4 = cidr net4 net4Len;

    net6 = "fd10:244::";
    # The Controller Manager default node CIDR length is /64,
    # and the distance between the network length and the pod mask cannot be more than /16.
    net6Len = 64 - 16;
    cidr6 = cidr net6 net6Len;
  };

  service = rec {
    net4 = "10.96.0.0";
    net4Len = 16;
    cidr4 = cidr net4 net4Len;

    net6 = "fd10:96::";
    # The API server won't start if the subnet is larger than /108.
    net6Len = 112;
    cidr6 = cidr net6 net6Len;
  };

  external = rec {
    net4 = local 0 0;
    net4Len = 16;
    cidr4 = cidr net4 net4Len;

    # NAT'd services:
    nat = {
      ingress = [80 443];
      minecraft = [19132];
    };

    # External services:
    ingress = local 4 43;
    minecraft = local 19 132;

    # Internal services:
    vector = local 5 5;
  };

  uplink = let
    pick = matrix: map builtins.head matrix;
  in {
    gw4 = local 1 1;
    gw6 = "fe80::200:5eff:fe00:103";

    dns4 = let
      cloudflare = ["1.1.1.1" "1.0.0.1"];
      google = ["8.8.8.8" "8.8.4.4"];
      quad9 = ["9.9.9.9" "149.112.112.112"];
    in {
      inherit cloudflare;
      one = pick [cloudflare];
      two = pick [cloudflare quad9];
      three = pick [cloudflare google quad9];
    };
    dns6 = let
      cloudflare = ["2606:4700:4700::1111" "2606:4700:4700::1001"];
      google = ["2001:4860:4860::8888" "2001:4860:4860::8844"];
      quad9 = ["2620:fe::fe" "2620:fe::9"];
    in {
      inherit cloudflare;
      one = pick [cloudflare];
      two = pick [cloudflare quad9];
      three = pick [cloudflare google quad9];
    };
  };
}
