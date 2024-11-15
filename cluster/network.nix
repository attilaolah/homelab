{self}: let
  inherit (self.lib) cidr;
in {
  node = rec {
    net4 = "10.8.0.0";
    net4Len = 8;
    cidr4 = cidr net4 net4Len;

    net6 = "fd10:8::";
    net6Len = 64;
    cidr6 = cidr net6 net6Len;
  };

  pod = rec {
    net4 = "10.244.0.0";
    net4Len = 16;
    cidr4 = cidr net4 net4Len;

    net6 = "fd10:244::";
    net6Len = 56;
    cidr6 = cidr net6 net6Len;
  };

  service = rec {
    net4 = "10.96.0.0";
    net4Len = 12;
    cidr4 = cidr net4 net4Len;

    net6 = "fd10:96::";
    net6Len = 108;
    cidr6 = cidr net6 net6Len;
  };

  external = rec {
    net4 = "10.10.0.0";
    net4Len = 24;
    cidr4 = cidr net4 net4Len;

    # NAT'd services:
    nat = {
      "80" = ingress;
      "443" = ingress;
    };

    # Named services:
    ingress = "10.10.10.10";
    vector = "10.10.0.5";
  };

  uplink = let
    pick = matrix: map builtins.head matrix;
  in {
    gw4 = "10.0.0.1";
    gw6 = "fe80::3a35:fbff:fe0d:c7bf";

    dns4 = let
      cloudflare = ["1.1.1.1" "1.0.0.1"];
      google = ["8.8.8.8" "8.8.4.4"];
      quad9 = ["9.9.9.9" "149.112.112.112"];
    in {
      inherit cloudflare;
      two = pick [cloudflare quad9];
      three = pick [cloudflare google quad9];
    };
    dns6 = let
      cloudflare = ["2606:4700:4700::1111" "2606:4700:4700::1001"];
      google = ["2001:4860:4860::8888" "2001:4860:4860::8844"];
      quad9 = ["2620:fe::fe" "2620:fe::9"];
    in {
      inherit cloudflare;
      two = pick [cloudflare quad9];
      three = pick [cloudflare google quad9];
    };
  };
}
