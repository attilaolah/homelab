{
  inventory.machines = let
    inherit (data) ids machines tags;

    data = import ./data.nix;
    acme = tags.acme or [];
    acme_client = tags.acme_client or [];
    caddy = tags.caddy or [];
    openbao = tags.openbao or [];
    openbao_client = tags.openbao_client or [];
    tpm12 = tags.tpm12 or [];
    tpm12_bootstrap = tags.tpm12_bootstrap or [];
  in
    # Make sure no tags contains a machine that is not registered.
    assert (builtins.filter
      (machine: !(builtins.hasAttr machine ids))
      (builtins.concatLists (builtins.attrValues tags)))
    == [];
    # Make sure ACME servers only run on machines with TPM 1.2 hardware.
    assert builtins.all (machine: builtins.elem machine tpm12) acme;
    # Make sure ACME clients only run on machines without TPM hardware.
    assert builtins.all (machine: !(builtins.elem machine (tpm12 ++ tpm12_bootstrap))) acme_client;
    # OpenBao Raft requires the TPM-issued service identity.
    assert builtins.all (machine: builtins.elem machine tpm12) openbao;
    assert builtins.all (machine: builtins.elem machine caddy && !(builtins.elem machine openbao)) openbao_client;
      builtins.mapAttrs (_name: machine: {
        deploy.targetHost = "root@${machine.ip}";
        tags = machine.tags;
      })
      machines;
}
