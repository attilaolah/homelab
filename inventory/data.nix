let
  inherit (builtins) attrNames elem mapAttrs;

  # ALL machines need to be registered here.
  # Numbers are used to build the network suffix, i.e. 8 -> 192.168.1.8.
  ids = {
    acer = 121;
    aloe = 116;
    aria = 102;
    hoya = 104;
    ilex = 103;
    inga = 105;
    iris = 101;
    rosa = 120;
    sida = 122;
    unio = 117;
  };

  # Additional tags per machine.
  tags = {
    acme = ["acer"];
    laptop = ["acer" "rosa" "sida"];
    tpm12 = ["acer" "hoya" "inga" "iris"];
    watchdog = ["acer" "hoya" "inga" "iris" "rosa"];
  };

  # Machines that are on the internal network.
  # These should eventually be moved to the external network after initial setup.
  internal = [];

  ip4 = x: y: "192.168.${toString x}.${toString y}";

  machines =
    mapAttrs (name: id: let
      lan =
        if elem name internal
        then 0
        else 1;
      ip = ip4 lan id;
    in {
      inherit ip;

      tags = builtins.filter (tag: elem name tags.${tag}) (attrNames tags);
    })
    ids;
in {
  inherit ids internal machines tags;
}
