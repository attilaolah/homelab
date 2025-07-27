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

  oaPort = 8443;
  queryPort = 16686;

  # Shared emptyDir mount for storing CA certificates.
  # A read-only version is mounted under /etc/ssl/certs, and a read-write version
  # under /etc/ssl/certs/new, which is populated by init-containers with a combined CA bundle.
  certsMount = {
    name = "certs";
    mountPath = "/etc/ssl/certs";
    readOnly = true;
  };
  certsMountNew = {
    inherit (certsMount) name;
    mountPath = "${certsMount.mountPath}/new";
  };

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
      port = oaPort;
      targetPort = oaPort;
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
      containerPort = oaPort;
      args = ["--config" "/etc/oauth2-proxy/oauth2-proxy.cfg"];
      extraEnv = [
        {
          name = "OAUTH2_PROXY_CLIENT_SECRET";
          valueFrom.secretKeyRef = {
            name = "${name}-secrets";
            key = "oauth2_client_secret";
          };
        }
        {
          name = "OAUTH2_PROXY_COOKIE_SECRET";
          valueFrom.secretKeyRef = {
            name = "${name}-secrets";
            key = "oauth2_cookie_secret";
          };
        }
        {
          name = "OAUTH2_PROXY_REDIS_PASSWORD";
          valueFrom.secretKeyRef = {
            name = "${name}-secrets";
            key = "oauth2_redis_password";
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

        https_address = "[::]:${toString oaPort}"
        tls_cert_file = "${k.pki.crt}"
        tls_key_file = "${k.pki.key}"

        cookie_secure = "true"
        cookie_samesite = "strict"
        cookie_name = "__Host-${name}"

        session_store_type = "redis"
        redis_connection_url = "rediss://oauth-db.redis.svc:6379"

        upstreams = ["https://localhost:${toString queryPort}"]

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

    initContainers = [
      {
        inherit (k.container) securityContext;

        name = "init-ca";
        image = "alpine:${v.alpine.docker}";
        args = let
          bundle = "ca-certificates.crt";
        in [
          "sh"
          "-c"
          # The internal CA is used for trusting the upstream service.
          "cat ${certsMount.mountPath}/${bundle} ${k.pki.ca} > ${certsMountNew.mountPath}/${bundle}"
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
        volumeMounts = [
          certsMountNew
          k.pki.mount
        ];
      }
    ];

    extraVolumes = [
      {
        inherit (certsMount) name;
        emptyDir.medium = "Memory";
      }
    ];
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

  extraObjects = [
    (k.api "Service" (let
      labels = k.annotations.group "app.kubernetes.io" {
        inherit name;
        instance = name;
        component = "query";
      };
    in {
      metadata = {inherit name labels;};
      spec = {
        selector = labels;
        ports = [
          {
            name = "query";
            port = 443;
            protocol = "TCP";
            targetPort = queryPort;
          }
        ];
      };
    }))
  ];
}
