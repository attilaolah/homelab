{
  config,
  inputs,
  lib,
  ...
}: let
  inherit (config.networking) hostName domain;

  inventory = import (inputs.self + /inventory/data.nix);
  pkiDirectory = "/run/pki/tls";

  tls = {
    # The issuer owns leaf renewal.  OpenBao reads its output directly, while
    # the shared root CA remains at the canonical tls-ca Clan variable path.
    ca = config.clan.core.vars.generators."tls-ca".files."ca.crt".path;
    certificate = "${pkiDirectory}/tls.crt";
    key = "${pkiDirectory}/tls.key";
  };
in {
  inherit domain hostName inventory pkiDirectory tls;

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
