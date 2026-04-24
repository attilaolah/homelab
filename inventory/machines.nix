{
  inventory.machines = let
    # ALL machines need to be registered here.
    # Numbers are used to build the network suffix, i.e. 8 -> 192.168.1.8.
    ids = {
      acer = 121;
      aloe = 116;
      aria = 241;
      hoya = 244;
      ilex = 103;
      inga = 243;
      iris = 101;
      rosa = 120;
      unio = 117;
    };

    # Additional tags per machine.
    tags = {
      acer = ["laptop"];
      rosa = ["laptop"];
    };

    # Machines that are on the internal network.
    # These should eventually be moved to the external network after initial setup.
    internal = ["aria" "inga" "hoya"];
  in
    builtins.mapAttrs (name: id: let
      lan =
        if builtins.elem name internal
        then 0
        else 1;
      ip = ip4 lan id;

      ip4 = x: y: "192.168.${toString x}.${toString y}";
    in {
      deploy.targetHost = "root@${ip}";
      tags = tags.${name} or [];
    })
    ids;
}
