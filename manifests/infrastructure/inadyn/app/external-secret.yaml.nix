{
  cluster,
  k,
  self,
  ...
}: let
  inherit (self.lib) yaml;
in
  k.external-secret ./. {
    data."values.yaml" = yaml.format {
      inadynConfig = with cluster; ''
        period = 480

        # A ${domain}
        provider cloudflare.com {
            hostname = ${domain}
            username = ${domain}
            password = {{ .cloudflare_api_token }}
            ttl = 1 # automatic
        }

        # CNAME duckdns.${domain}
        provider duckdns.org {
            hostname = dornhaus.duckdns.org
            username = {{ .duckdns_token }}
        }
      '';
    };
  }
