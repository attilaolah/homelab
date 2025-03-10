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

  tlsPath = "/etc/tls";
in {
  query = let
    component = "query";
    tlsSecret = "${name}-${component}-tls";
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
        "nginx.ingress.kubernetes.io/proxy-ssl-name" = "${name}-${component}";
        "nginx.ingress.kubernetes.io/proxy-ssl-secret" = "${namespace}/${tlsSecret}";
        "nginx.ingress.kubernetes.io/proxy-ssl-server-name" = "on";
        "nginx.ingress.kubernetes.io/proxy-ssl-verify" = "on";
        # NGINX: Increase header size since auth cookies are way too large.
        "nginx.ingress.kubernetes.io/proxy-buffer-size" = "16k";
        "nginx.ingress.kubernetes.io/proxy-buffers" = "8 16k";
        # Homepage
        "gethomepage.dev/enabled" = "true";
        "gethomepage.dev/name" = "Jaeger";
        "gethomepage.dev/description" = "Distributed tracing tool";
        "gethomepage.dev/group" = "Cluster Management";
        "gethomepage.dev/icon" = "${name}.svg";
        "gethomepage.dev/pod-selector" =
          concatStringsSep ","
          (attrValues (mapAttrs (key: val: "app.kubernetes.io/${key}=${val}") {
            inherit name component;
            instance = name;
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
        redirect_url = "https://${domain}/${name}/auth/callback"
        code_challenge_method = "S256"
        email_domains = "${domain}"

        reverse_proxy = true
        proxy_prefix = "${basePath}/auth"

        tls_cert_file = "${tlsPath}/tls.crt"
        tls_key_file = "${tlsPath}/tls.key"

        cookie_secure = "true"
        cookie_samesite = "strict"
        cookie_name = "__Host-jaeger-auth"

        upstreams = ["http://localhost:16686"]

        skip_provider_button = "true"
      '';

      # TODO:
      # allowed_roles = "jaeger-ui:view"

      extraSecretMounts = [
        {
          name = "tls";
          secretName = tlsSecret;
          mountPath = tlsPath;
          readOnly = true;
        }
      ];
      # resources: {} # todo
    };
  };

  collector = let
    component = "collector";
    tlsSecret = "${name}-${component}-tls";
  in {
    enabled = true;
    service = {
      otlp = {
        grpc.name = "otlp-grpc";
        http.name = "otlp-http";
      };
      zipkin = null;
    };
    cmdlineParams = {
      "collector.otlp.grpc.tls.enabled" = "true";
      "collector.otlp.grpc.tls.cert" = "${tlsPath}/tls.crt";
      "collector.otlp.grpc.tls.key" = "${tlsPath}/tls.key";
      "collector.otlp.grpc.tls.client-ca" = "${tlsPath}/ca.crt";
      "collector.otlp.http.tls.enabled" = "true";
      "collector.otlp.http.tls.cert" = "${tlsPath}/tls.crt";
      "collector.otlp.http.tls.key" = "${tlsPath}/tls.key";
      "collector.otlp.http.tls.client-ca" = "${tlsPath}/ca.crt";
    };
    extraSecretMounts = [
      {
        name = "tls";
        secretName = tlsSecret;
        mountPath = tlsPath;
        readOnly = true;
      }
    ];
  };

  networkPolicy.enabled = true;
}
