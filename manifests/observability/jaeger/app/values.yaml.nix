# https://artifacthub.io/packages/helm/jaegertracing/jaeger#configuration
{
  cluster,
  k,
  v,
  ...
}: let
  inherit (cluster) domain;

  name = k.appname ./.;
  namespace = k.nsname ./.;

  pki = "/etc/tls";
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
      containerPort = 443;
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
        proxy_prefix = "${basePath}/auth"

        tls_cert_file = "${pki}/tls.crt"
        tls_key_file = "${pki}/tls.key"

        cookie_secure = "true"
        cookie_samesite = "strict"
        cookie_name = "__Host-${name}"

        upstreams = ["http://localhost:16686"]

        skip_provider_button = "true"
      '';

      extraSecretMounts = [
        {
          name = "tls";
          secretName = tlsSecret;
          mountPath = pki;
          readOnly = true;
        }
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
    protos = fn: (fn "grpc") // (fn "http");
  in {
    enabled = true;
    service = {
      otlp = protos (proto: {${proto}.name = "otlp-${proto}";});
      zipkin = null;
    };
    cmdlineParams = protos (proto: let
      prefix = "collector.otlp.${proto}.tls";
    in {
      "${prefix}.enabled" = "true";
      "${prefix}.cert" = "${pki}/tls.crt";
      "${prefix}.key" = "${pki}/tls.key";
      "${prefix}.client-ca" = "${pki}/ca.crt";
    });
    extraSecretMounts = [
      {
        name = "tls";
        secretName = tlsSecret;
        mountPath = pki;
        readOnly = true;
      }
    ];
  };

  agent.enabled = false;
}
