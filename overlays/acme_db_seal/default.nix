{clan-core}: final: _prev: let
  pki = import ../../modules/lib/pki.nix;
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
      acmeDirectory = pki.acme.dir;
      acmeGocryptfsConfig = "${pki.step.dir}/db.crypt/gocryptfs.conf";
    };
  };
}
