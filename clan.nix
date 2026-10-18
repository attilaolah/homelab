{
  imports = [./inventory];

  machines = builtins.mapAttrs (_: _: {
    nixpkgs.overlays = [
      (import ./overlays/sqlite_cross_tests.nix)
    ];
  }) (import ./inventory/data.nix).machines;

  meta = {
    name = "locker";
    description = "Attila's bare metal homelab";
    domain = "dorn.haus";
  };
}
