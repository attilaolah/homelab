{
  inventory.machines = let
    inherit (builtins) all attrValues concatLists elem filter hasAttr mapAttrs;
    inherit (data) ids machines tags;

    data = import ./data.nix;
    unknownTaggedMachines =
      filter (machine: !(hasAttr machine ids))
      (concatLists (attrValues tags));
  in
    assert unknownTaggedMachines == [];
    assert all (machine: elem machine tags.tpm12) tags.acme;
      mapAttrs (_name: machine: {
        deploy.targetHost = "root@${machine.ip}";
        tags = machine.tags;
      })
      machines;
}
