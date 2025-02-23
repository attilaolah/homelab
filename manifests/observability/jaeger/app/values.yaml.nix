# https://artifacthub.io/packages/helm/jaegertracing/jaeger#configuration
{
  cluster,
  k,
  lib,
  ...
}: let
  inherit (builtins) attrValues mapAttrs;
  inherit (cluster) domain;
  inherit (lib.strings) concatStringsSep;

  name = k.appname ./.;
  namespace = k.nsname ./.;
in {
  strategy = "allinone";
  storage = {
    type = "memory";
    options.memory.max-traces = 10000;
  };

  query = let
    tlsSecret = "${name}-query-tls";
  in rec {
    enabled = true;
    basePath = "/${name}";
    service = {
      port = 443;
      targetPort = oAuthSidecar.containerPort;
    };
    ingress = {
      enabled = true;
      ingressClassName = "nginx";
      hosts = [domain];
      annotations = {
        # TLS
        "cert-manager.io/cluster-issuer" = "letsencrypt";
        # NGINX
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS";
        "nginx.ingress.kubernetes.io/proxy-ssl-name" = "jaeger-query";
        "nginx.ingress.kubernetes.io/proxy-ssl-secret" = "${namespace}/${tlsSecret}";
        "nginx.ingress.kubernetes.io/proxy-ssl-server-name" = "on";
        "nginx.ingress.kubernetes.io/proxy-ssl-verify" = "on";
        # Homepage
        "gethomepage.dev/enabled" = "true";
        "gethomepage.dev/name" = "Jaeger";
        "gethomepage.dev/description" = "Distributed tracing tool";
        "gethomepage.dev/group" = "Cluster Management";
        "gethomepage.dev/icon" = "${name}.svg";
        "gethomepage.dev/pod-selector" =
          concatStringsSep ","
          (attrValues (mapAttrs (key: val: "app.kubernetes.io/${key}=${val}") {
            inherit name;
            instance = name;
            component = "query";
          }));
      };
      tls = [
        {
          hosts = [domain];
          secretName = "${domain}-tls";
        }
      ];
    };
    oAuthSidecar = {
      enabled = true;
      image = {
        registry = "quay.io";
        repository = "oauth2-proxy/oauth2-proxy";
        tag = "v7.8.1"; # todo: renovate
      };
      pullPolicy = "IfNotPresent";
      containerPort = 443;
      args = [
        "--config"
        "/etc/oauth2-proxy/oauth2-proxy.cfg"
        "--client-secret"
        ''"$(CLIENT_SECRET)"''
        "--cookie-secret"
        ''"$(COOKIE_SECRET)"''
      ];
      extraEnv = [
        {
          name = "CLIENT_SECRET";
          valueFrom.secretKeyRef = {
            name = "${name}-secrets";
            key = "oauth2-client-secret";
          };
        }
        {
          name = "COOKIE_SECRET";
          valueFrom.secretKeyRef = {
            name = "${name}-secrets";
            key = "oauth2-cookie-secret";
          };
        }
      ];
      # TODO: Don't set the http_address; just use the https address.
      config = ''
        provider = "keycloak-oidc"
        client_id = "jaeger-ui"
        oidc_issuer_url = "https://${domain}/keycloak/realms/dornhaus"
        redirect_url = "https://${domain}/${name}/oauth2/callback"
        code_challenge_method = "S256"
        allowed_roles = "jaeger-ui:view"
        email_domains = "${domain}"

        proxy_prefix = "${basePath}"

        tls_cert_file = "/etc/tls/tls.crt"
        tls_key_file = "/etc/tls/tls.key"

        cookie_secure = "true"
        cookie_samesite = "strict"
        cookie_name = "__Host-jaeger-auth"

        upstreams = ["http://localhost:16686"]
      '';

      # TODO:
      # skip_provider_button = "false"

      extraSecretMounts = [
        {
          name = "tls";
          secretName = tlsSecret;
          mountPath = "/etc/tls";
          readOnly = true;
        }
      ];
      # resources: {} # todo
    };
  };

  networkPolicy.enabled = true;
}
