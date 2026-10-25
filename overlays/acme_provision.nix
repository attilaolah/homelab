{
  clan-core,
  domain,
  machineData,
}: final: _prev: let
  pki = import ../modules/lib/pki.nix;
  acme = import ../modules/tags/acme/common.nix {inherit pki;};
  template = import ../modules/lib/template.nix;
in {
  acme-provision = final.writeShellApplication {
    name = "acme-provision";
    runtimeInputs = [
      clan-core.packages.${final.stdenv.hostPlatform.system}.clan-cli
      final.coreutils
      final.gitMinimal
      final.gnused
      final.jq
    ];
    text = template ./acme_provision.sh {
      acmeDirectory = pki.acme.dir;
      acmeHostsEscaped = final.lib.escapeShellArgs (builtins.sort builtins.lessThan machineData.tags.acme);
      acmePort = toString acme.port;
      inherit domain;
      stepPath = acme.stepPath;
    };
  };
}
