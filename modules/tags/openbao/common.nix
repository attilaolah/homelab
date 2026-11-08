{
  config,
  inputs,
  lib,
  ...
}: let
  inherit (config.networking) hostName domain;

  inventory = import (inputs.self + /inventory/data.nix);
  pki = import (inputs.self + /modules/lib/pki.nix);

  fqdn = node: "${node}.node.${domain}";
  https = host: port: "https://${host}:${port}";

  host = fqdn hostName;
  nodes = {
    cluster = inventory.tags.openbao or [];
    client = inventory.tags.openbao_client or [];
  };
  ports = lib.mapAttrs (_: toString) {
    api = 8200;
    cluster = 8201;
  };
  addrs = lib.mapAttrs (_: https host) ports;

  tls = {
    # The issuer owns leaf renewal.  OpenBao reads its output directly, while
    # the shared root CA remains at the canonical tls-ca Clan variable path.
    ca = config.clan.core.vars.generators.${pki.cluster.ca.gen}.files.${pki.cluster.ca.crt}.path;
    issuer = pki.tpm.ca.crt;
    certificate = pki.tls.crt;
    key = pki.tls.key;
  };
in {
  inherit addrs domain fqdn host hostName https inventory nodes pki ports tls;

  module = {
    assertions = [
      {
        assertion = lib.hasAttrByPath ["systemd" "services" "issue-tls-certificate"] config;
        message = "The OpenBao tags require the tpm12 issue-tls-certificate service.";
      }
    ];
  };
}
