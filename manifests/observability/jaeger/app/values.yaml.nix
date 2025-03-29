# https://artifacthub.io/packages/helm/jaegertracing/jaeger#configuration
# https://github.com/jaegertracing/helm-charts/blob/main/charts/jaeger/values.yaml
{
  cluster,
  k,
  v,
  ...
}: let
  inherit (cluster) domain;

  name = k.appname ./.;
  namespace = k.nsname ./.;

  oauth2Port = 8443;

  tlsParams = prefix: {
    "${prefix}.tls.enabled" = "true";
    "${prefix}.tls.cert" = k.pki.crt;
    "${prefix}.tls.key" = k.pki.key;
    "${prefix}.tls.reload-interval" = "${toString (60 * 24)}h";
    "${prefix}.tls.min-version" = "1.3";
  };
in {
  query = let
    component = "query";
    tlsSecret = "${name}-${component}-tls";
  in {
    enabled = true;
    image.tag = v.jaeger-collector.docker;
    basePath = "/${name}";
    service = {
      port = oauth2Port;
      targetPort = oauth2Port;
    };

    # HTTP Client CA cannot be enabled since oauth-proxy cannot pass it.
    # https://github.com/oauth2-proxy/oauth2-proxy/issues/1901#issuecomment-1364004628
    cmdlineParams =
      (tlsParams "query.grpc")
      // (tlsParams "query.http")
      // {"query.grpc.tls.client-ca" = k.pki.ca;};

    extraSecretMounts = [(k.pki.mount // {secretName = tlsSecret;})];

    ingress = {
      enabled = true;
      ingressClassName = "nginx";
      hosts = [domain];
      annotations = with k.annotations;
        cert-manager
        // (ingress-nginx {
          inherit namespace;
          name = "${name}-${component}";
          secret = tlsSecret;
          # Increase header size to fit auth cookies.
          proxyBufferSize = "16k";
        })
        // (homepage {
          name = "Jaeger";
          description = "Distributed tracing tool";
          icon = name;
          group = "Cluster Management";
          selector = {
            inherit name component;
            instance = name;
          };
        });
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
        tag = v.oauth2-proxy.docker;
      };
      pullPolicy = "IfNotPresent";
      containerPort = 8443;
      args = ["--config" "/etc/oauth2-proxy/oauth2-proxy.cfg"];
      extraEnv = [
        {
          name = "OAUTH2_PROXY_CLIENT_SECRET";
          valueFrom.secretKeyRef = {
            name = "${name}-secrets";
            key = "oauth2-client-secret";
          };
        }
        {
          name = "OAUTH2_PROXY_COOKIE_SECRET";
          valueFrom.secretKeyRef = {
            name = "${name}-secrets";
            key = "oauth2-cookie-secret";
          };
        }
      ];
      config = ''
        provider = "keycloak-oidc"
        client_id = "monitoring"
        oidc_issuer_url = "https://${domain}/keycloak/realms/dh"
        redirect_url = "https://${domain}/${name}/auth/callback"
        code_challenge_method = "S256"
        email_domains = "${domain}"

        reverse_proxy = true
        proxy_prefix = "/${name}/auth"

        https_address = "[::]:${toString oauth2Port}"
        tls_cert_file = "${k.pki.crt}"
        tls_key_file = "${k.pki.key}"

        cookie_secure = "true"
        cookie_samesite = "strict"
        cookie_name = "__Host-${name}"

        upstreams = ["https://localhost:16686"]
        # TODO: Use caFiles from alpha config.
        ssl_upstream_insecure_skip_verify = true

        skip_provider_button = "true"
      '';

      extraSecretMounts = [
        (k.pki.mount
          // {
            name = "tls-sidecar";
            secretName = tlsSecret;
          })
      ];
      resources = {
        limits = {
          cpu = "200m";
          memory = "256Mi";
          ephemeral-storage = "2Gi";
        };
        requests = {
          cpu = "50m";
          memory = "128Mi";
          ephemeral-storage = "64Mi";
        };
      };
    };
  };

  collector = let
    component = "collector";
    tlsSecret = "${name}-${component}-tls";
  in {
    enabled = true;
    image.tag = v.jaeger-collector.docker;
    service = {
      otlp = {
        grpc.name = "otlp-grpc";
        http.name = "otlp-http";
      };
      zipkin = null;
    };
    cmdlineParams =
      (tlsParams "collector.otlp.grpc")
      // {"collector.otlp.grpc.tls.client-ca" = k.pki.ca;};
    extraSecretMounts = [(k.pki.mount // {secretName = tlsSecret;})];
  };

  agent.enabled = false;

  storage.type = "memory";
  provisionDataStore = {
    cassandra = false;
    elasticsearch = false;
    kafka = false;
  };
}
