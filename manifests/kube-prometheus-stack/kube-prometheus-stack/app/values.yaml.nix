# https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml
{
  cluster,
  k,
  lib,
  v,
  ...
}: let
  inherit (cluster) domain;
  inherit (lib.strings) concatStringsSep replaceStrings;

  instance = k.appname ./.;
  namespace = k.nsname ./.;
  group = "Cluster Management";

  ingressClassName = "nginx";
  ingressSecretName = "${domain}-tls";
  secrets = "${instance}-secrets";
  oauthConfig = "${instance}-oauth-config";
  hosts = [domain];
  tls = [
    {
      inherit hosts;
      secretName = ingressSecretName;
    }
  ];

  oauth2Port = 8443;
  prometheusPort = 9090;

  # Shared emptyDir mount for storing CA certificates.
  # This is populated by an initContainers with root CAs.
  certsMount = {
    name = "certs";
    mountPath = "/etc/ssl/certs";
  };

  localFile = path: "$__file{${path}}";
in {
  # Grafana subchart config defaults:
  # https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
  grafana = let
    name = "grafana";
    fullName = "${instance}-${name}";
    path = "/${name}";
    secretName = "${name}-tls";
    port = 3000;
    localAddr = "https://localhost:${toString port}";
  in rec {
    ingress = {
      inherit hosts ingressClassName path tls;

      enabled = true;
      annotations = with k.annotations;
        cert-manager
        // (ingress-nginx {
          inherit namespace;
          name = fullName;
          secret = secretName;
        })
        // (homepage {
          inherit group;
          name = "Grafana";
          description = "Observability platform";
          icon = name;
          selector = {inherit name instance;};
        });
    };

    admin = let
      prefix = "${name}-admin";
    in {
      userKey = "${prefix}-user";
      passwordKey = "${prefix}-password";
      existingSecret = "${instance}-secrets";
    };

    # Grafana's primary configuration.
    "grafana.ini" = {
      server = rec {
        serve_from_sub_path = true;
        root_url = "${protocol}://${domain}${path}";
        protocol = "https";
        cert_file = k.pki.crt;
        cert_key = k.pki.key;

        # Do not enforce the domain.
        # This avoids sidecar requests being redirected to go through the ingress.
        # For requests coming through the ingress, the controller already enforces the domain.
        enforce_domain = false;
      };
      "auth.generic_oauth" = let
        idp = "https://${domain}/keycloak/realms/dh/protocol/openid-connect";
      in {
        enabled = true;
        name = "OAuth";
        scopes = concatStringsSep " " [
          "email"
          "openid"
          "profile"
        ];
        email_attribute_name = "email";
        login_attribute_path = "preferred_username";
        name_attribute_path = "join(' ', [firstName, lastName])";
        role_attribute_path = "('Admin')"; # everyone is an admin, for now
        client_id = "monitoring";
        client_secret = localFile "/etc/secrets/oauth2-client-secret";
        allow_sign_up = true;
        allowed_domains = hosts;
        auth_url = "${idp}/auth";
        token_url = "${idp}/token";
        api_url = "${idp}/userinfo";
        use_pkce = true;
        use_refresh_token = true;
      };
    };

    sidecar = let
      script = "/usr/sbin/update-ca-certificates";
      env.REQUESTS_CA_BUNDLE = "/etc/ssl/cert.pem";
      extraMounts = [
        rec {
          name = "tls";
          mountPath = "/usr/local/share/ca-certificates/${subPath}";
          subPath = k.pki.files.ca;
          readOnly = true;
        }
        certsMount
      ];

      reload = what: "${localAddr}${path}/api/admin/provisioning/${what}/reload";
    in {
      dashboards = {
        inherit env extraMounts script;
        reloadURL = reload "dashboards";
      };
      datasources = {
        inherit env extraMounts script;
        reloadURL = reload "datasources";
        # Prometheus Datasource installed manually below.
        defaultDatasourceEnabled = false;
      };
    };

    additionalDataSources = let
      prometheus = "prometheus";
      jaeger = "jaeger";
      loki = "loki";

      secureJsonData = with k.pki; {
        tlsCACert = localFile ca;
        tlsClientCert = localFile crt;
        tlsClientKey = localFile key;
      };
      version = 1;
    in [
      {
        inherit secureJsonData version;
        name = "Prometheus";
        type = prometheus;
        uid = prometheus;
        editable = false;
        url = "https://${instance}-${prometheus}:${toString prometheusPort}/${prometheus}";
        jsonData = {
          tlsAuth = true;
          tlsAuthWithCACert = true;
        };
      }
      {
        inherit secureJsonData version;
        name = "Jaeger";
        type = jaeger;
        uid = jaeger;
        editable = false;
        url = "https://${jaeger}-query-https.observability.svc/${jaeger}";
        jsonData = {
          tlsAuth = true;
          tlsAuthWithCACert = true;
          tracesToMetrics.datasourceUid = prometheus;
        };
      }
      {
        type = loki;
        name = "Loki";
        url = "http://${loki}.observability.svc:3100";
      }
    ];

    livenessProbe = {
      exec.command = with k.pki; [
        "curl"
        "--silent"
        "${localAddr}/api/health"
        "--cert"
        crt
        "--key"
        key
        "--cacert"
        ca
      ];
      httpGet = null;
    };
    readinessProbe = livenessProbe;

    extraSecretMounts = [
      rec {
        name = "secrets";
        mountPath = "/etc/${name}";
        secretName = "${instance}-${name}";
        readOnly = true;
      }
      (k.pki.mount // {inherit secretName;})
    ];

    extraContainerVolumes = [
      {
        name = "certs";
        emptyDir.medium = "Memory";
      }
    ];

    serviceMonitor = {
      path = "${path}/metrics";
      scheme = "https";
      tlsConfig = {
        cert.secret = {
          name = secretName;
          key = k.pki.files.crt;
        };
        keySecret = {
          name = secretName;
          key = k.pki.files.key;
        };
        client_ca.secret = {
          name = secretName;
          key = k.pki.files.ca;
        };
        serverName = fullName;
      };
    };
  };

  # Prometheus subchart config defaults:
  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus/values.yaml
  prometheus = let
    name = "prometheus";
    fullName = "${instance}-${name}";
    path = "/${name}";
    secretName = "${name}-tls";
    secretMount = k.pki.mount // {name = "secret-${secretName}";};
  in rec {
    ingress = {
      inherit hosts ingressClassName tls;

      enabled = true;
      paths = [path];
      pathType = "ImplementationSpecific";
      servicePort = oauth2Port;
      annotations = with k.annotations;
        cert-manager
        // (ingress-nginx {
          inherit namespace;
          name = fullName;
          secret = secretName;
          # Increase header size to fit auth cookies.
          proxyBufferSize = "16k";
        })
        // (homepage {
          inherit group;
          name = "Prometheus";
          description = "Monitoring system";
          icon = name;
          selector = {inherit name instance;};
        });
    };

    service.additionalPorts = [
      {
        name = "oauth2-proxy";
        port = oauth2Port;
        targetPort = oauth2Port;
        appProtocol = "https";
      }
    ];

    prometheusSpec = let
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
      securityContext = {
        allowPrivilegeEscalation = false;
        capabilities.drop = ["ALL"];
        readOnlyRootFilesystem = true;
      };
    in {
      retention = "28d";
      routePrefix = path;
      externalUrl = "https://${domain}${path}";

      storageSpec.emptyDir.sizeLimit = "64Gi";

      web.tlsConfig = {
        cert.secret = {
          name = secretName;
          key = k.pki.files.crt;
        };
        keySecret = {
          name = secretName;
          key = k.pki.files.key;
        };
        client_ca.secret = {
          name = secretName;
          key = k.pki.files.ca;
        };
        # NOTE: RequireAndVerifyClientCert causes startup probes to fail.
        clientAuthType = "VerifyClientCertIfGiven";
      };

      containers = let
        configFile = "oauth2_proxy.conf";
        configPath = "/etc/${configFile}";
      in [
        {
          inherit resources securityContext;

          name = "oauth2-proxy";
          image = "quay.io/oauth2-proxy/oauth2-proxy:${v.oauth2-proxy.docker}";
          args = ["--config" configPath];
          env = [
            {
              name = "OAUTH2_PROXY_CLIENT_SECRET";
              valueFrom.secretKeyRef = {
                name = secrets;
                key = "oauth2-client-secret";
              };
            }
            {
              name = "OAUTH2_PROXY_COOKIE_SECRET";
              valueFrom.secretKeyRef = {
                name = secrets;
                key = "oauth2-cookie-secret";
              };
            }
          ];
          ports = [
            {
              name = "oauth2-proxy";
              containerPort = oauth2Port;
              protocol = "TCP";
            }
          ];
          # Loading files from /etc/prometheus doesn't seem to work.
          # Maybe because of the multiple levels of symbolic links, who knows, but avoiding symlinks seems to work.
          volumeMounts = [
            {
              name = "configmap-${oauthConfig}";
              mountPath = configPath;
              subPath = name;
              readOnly = true;
            }
            secretMount
            certsMount
          ];
        }
      ];
      initContainers = let
        ingressCrt = "/etc/ssl/ingress.crt";
      in [
        {
          inherit resources securityContext;

          name = "init-ca-certificates";
          image = "busybox:${v.busybox.docker}";
          # The ingress certificate is used only for trusting Keycloak.
          # The internal CA is used for trusting the upstream service (Prometheus).
          args = ["sh" "-c" "cat ${ingressCrt} ${k.pki.ca} > ${certsMount.mountPath}/ca-certificates.crt"];
          volumeMounts = [
            {
              name = "secret-${replaceStrings ["."] ["-"] ingressSecretName}";
              mountPath = ingressCrt;
              subPath = k.pki.files.crt;
              readOnly = true;
            }
            secretMount
            certsMount
          ];
        }
      ];

      secrets = [secretName ingressSecretName];
      configMaps = [oauthConfig];
      volumes = [
        {
          name = "certs";
          emptyDir.medium = "Memory";
        }
      ];
    };

    serviceMonitor = {
      scheme = "https";
      tlsConfig = {
        inherit (prometheusSpec.web.tlsConfig) cert keySecret;
        ca = prometheusSpec.web.tlsConfig.client_ca;
        serverName = fullName;
      };
    };
  };

  cleanPrometheusOperatorObjectNames = true;

  extraManifests =
    (map (name:
      k.api "Certificate.cert-manager.io" {
        metadata = {inherit name;};
        spec = {
          secretName = "${name}-tls";
          issuerRef = {
            kind = "ClusterIssuer";
            name = "internal-ca";
          };
          commonName = name;
          dnsNames = [
            "${instance}-${name}"
            # Allow sidecars to connect via the loopback interface:
            "localhost"
          ];
        };
      }) [
      "grafana"
      "prometheus"
      "alertmanager"
    ])
    ++ [
      (k.api "ConfigMap" {
        metadata.name = oauthConfig;
        data.prometheus = let
          name = "prometheus";
        in ''
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

          upstreams = ["https://localhost:${toString prometheusPort}"]

          skip_provider_button = "true"
        '';
      })
    ];
}
