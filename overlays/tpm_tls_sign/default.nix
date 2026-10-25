{
  clan-core,
  intermediateCaExt,
}: final: _prev: let
  pki = import ../../modules/lib/pki.nix;
  template = import ../../modules/lib/template.nix;
in {
  tpm-tls-sign = final.writeShellApplication {
    name = "tpm-tls-sign";
    runtimeInputs = [
      clan-core.packages.${final.stdenv.hostPlatform.system}.clan-cli
      final.coreutils
      final.gitMinimal
      final.openssl
    ];
    text = template ./sign.sh {
      clusterCaCertificateFile = pki.cluster.ca.crt;
      clusterCaGenerator = pki.cluster.ca.gen;
      inherit intermediateCaExt;
      tpmCaCertificateFile = builtins.baseNameOf pki.tpm.ca.crt;
      tpmCaCsr = pki.tpm.ca.csr;
      tpmCaCsrFile = builtins.baseNameOf pki.tpm.ca.csr;
      tpmCaKey = pki.tpm.ca.key;
      tpmCaKeyFile = builtins.baseNameOf pki.tpm.ca.key;
      tpmCaSerialFile = "ca.srl";
      tpmGenerator = "tpm";
    };
  };
}
