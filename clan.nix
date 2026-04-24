{
  imports = [
    ./inventory/instances.nix
    ./inventory/machines.nix
  ];

  meta = {
    name = "locker";
    description = "Attila's bare metal homelab";
    domain = "dorn.haus";
  };
}
