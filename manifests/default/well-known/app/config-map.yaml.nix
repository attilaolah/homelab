{
  cluster,
  k,
  lib,
  ...
}:
k.api "ConfigMap" (let
  inherit (cluster) domain;
  inherit (lib.strings) escape toJSON;

  name = k.appname ./.;
  labels = import ./labels.nix;
in {
  metadata = {inherit name labels;};
  data = {
    config = let
      ok = toJSON {
        subject = "acct:$account@${domain}";
        links = [
          {
            "rel" = "http://openid.net/specs/connect/1.0/issuer";
            "href" = "https://${domain}/keycloak/realms/dh";
          }
        ];
      };
      notFound = toJSON {
        code = 404;
        error = "resource not found";
      };
    in ''
      map $query_string $account {
          ~resource=acct(%3[Aa]|:)(?P<user>.+?)(%40|@)${escape ["."] domain}$ $user;
      }

      server {
          listen 8443 ssl;
          listen [::]:8443 ssl;
          server_name ${domain};

          ssl_certificate ${k.pki.crt};
          ssl_certificate_key ${k.pki.key};
          ssl_client_certificate ${k.pki.ca};
          ssl_verify_client on;

          location /.well-known/webfinger {
              default_type application/json;

              if ($account) {
                  return 200 '${escape ["'"] ok}';
              }

              return 404 '${notFound}';
          }
      }
    '';
  };
})
