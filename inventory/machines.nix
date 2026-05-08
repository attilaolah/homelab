{
  inventory.machines = let
    inherit (builtins) all attrValues concatLists elem filter hasAttr mapAttrs;
    inherit (data) ids machines tags;

    data = import ./data.nix;
    acme = tags.acme or [];
    acme_client = tags.acme_client or [];
    tpm12 = tags.tpm12 or [];
    tpm12_bootstrap = tags.tpm12_bootstrap or [];
  in
    # Make sure no tags contains a machine that is not registered.
    assert (filter (machine: !(hasAttr machine ids)) (concatLists (attrValues tags))) == [];
    # Make sure ACME servers only run on machines with TPM 1.2 hardware.
    assert all (machine: elem machine tpm12) acme;
    # Make sure ACME clients only run on machines without TPM hardware.
    assert all (machine: !(elem machine (tpm12 ++ tpm12_bootstrap))) acme_client;
      mapAttrs (_name: machine: {
        deploy.targetHost = "root@${machine.ip}";
        tags = machine.tags;
      })
      machines;
}
