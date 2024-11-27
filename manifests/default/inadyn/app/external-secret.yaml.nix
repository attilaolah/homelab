{
  k,
  v,
  self,
  ...
}: let
  inherit (self.lib) cluster yaml;
in
  k.external-secret ./. {
    data."values.yaml" = yaml.format {
      image.tag = "v${v.inadyn-app}";
      inadynConfig = ''
        period = 480

        provider cloudflare.com { # main
            hostname = ${cluster.domain}
            username = ${cluster.domain}
            password = {{ .cloudflare_api_token }}
            ttl = 1 # automatic
        }

        provider duckdns.org { # backup
            hostname = dornhaus.duckdns.org
            username = {{ .duckdns_token }}
        }
      '';
    };
  }
