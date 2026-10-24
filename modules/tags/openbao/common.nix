{
  config,
  inputs,
  lib,
  ...
}: let
  inherit (config.networking) hostName domain;

  inventory = import (inputs.self + /inventory/data.nix);
  pki = import (inputs.self + /modules/lib/pki.nix);

  tls = {
    # The issuer owns leaf renewal.  OpenBao reads its output directly, while
    # the shared root CA remains at the canonical tls-ca Clan variable path.
    ca = config.clan.core.vars.generators.${pki.cluster.ca.gen}.files.${pki.cluster.ca.crt}.path;
    certificate = pki.tls.crt;
    key = pki.tls.key;
  };
in {
  inherit domain hostName inventory pki tls;

  module = {
    assertions = [
      {
        assertion = lib.hasAttrByPath ["systemd" "services" "issue-tls-certificate"] config;
        message = "The OpenBao tags require the tpm12 issue-tls-certificate service.";
      }
    ];

    systemd.tmpfiles.rules = ["d /run/openbao 0700 root root - -"];
  };
}
