let
  lib = "/var/lib";
  pki = "/run/pki";
  tls = "${pki}/tls";
  tpm = "${lib}/pki/tpm";
in {
  dir = pki;

  tls = let
    bn = "${tls}/tls";
  in {
    dir = tls;
    crt = "${bn}.crt";
    key = "${bn}.key";
  };
  acme.dir = "${pki}/acme";

  tpm = {
    dir = tpm;
    ca = let
      bn = "${tpm}/ca";
    in {
      crt = "${bn}.crt";
      key = "${bn}.key";
      csr = "${bn}.csr";
    };
  };

  step.dir = "${lib}/step-ca";

  cluster.ca = {
    gen = "tls-ca";
    crt = "ca.crt";
    key = "ca.key";
  };
}
