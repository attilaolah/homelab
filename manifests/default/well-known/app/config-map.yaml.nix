{
  cluster,
  k,
  lib,
  ...
}:
k.api "ConfigMap" (let
  inherit (cluster) domain;

  name = k.appname ./.;
  labels = import ./labels.nix;
in {
  metadata = {inherit name labels;};
  data = {
    config = ''
      map $query_string $account {
          ~resource=acct(%3[Aa]|:)(?P<user>.+?)(%40|@)${lib.strings.escape ["."] domain}$ $user;
      }

      server {
          listen 8443 ssl;
          listen [::]:8443 ssl;
          server_name ${domain};

          ssl_certificate /etc/tls/tls.crt;
          ssl_certificate_key /etc/tls/tls.key;
          ssl_client_certificate /etc/tls/ca.crt;
          ssl_verify_client on;

          location /.well-known/webfinger {
              default_type application/json;

              if ($account) {
                  return 200 '{"subject":"acct:$account@${domain}","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://${domain}/keycloak/realms/dh"}]}';
              }

              return 404 '{"code":404,"error":"resource not found"}';
          }
      }
    '';
  };
})
