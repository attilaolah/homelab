{clan-core}: final: _prev: let
  template = import ../../modules/lib/template.nix;
in {
  acme-db-seal = final.writeShellApplication {
    name = "acme-db-seal";
    runtimeInputs = [
      clan-core.packages.${final.stdenv.hostPlatform.system}.clan-cli
      final.coreutils
      final.gitMinimal
    ];
    text = template ./seal.sh {
      acmeDirectory = (import ../../modules/lib/pki.nix).acme.dir;
    };
  };
}
