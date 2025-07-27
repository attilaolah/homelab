args @ {k, ...}:
k.api "ConfigMap" (let
  name = k.appname ./.;
  inherit (import ./values.nix args) labels config;
in {
  metadata = {inherit name labels;};
  data.${config} = ''
    port 0
    tls-port 6379

    tls-cert-file /etc/tls/tls.crt
    tls-key-file /etc/tls/tls.key
    # NOTE: OAuth2 Proxy currently can't send client certificates.
    tls-auth-clients no
  '';
})
