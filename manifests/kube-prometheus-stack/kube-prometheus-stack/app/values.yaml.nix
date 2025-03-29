{
  cluster,
  k,
  lib,
  v,
  ...
}: let
  inherit (builtins) attrValues mapAttrs;
  inherit (cluster) domain;
  inherit (lib.strings) concatStringsSep replaceStrings;

  instance = k.appname ./.;
  namespace = k.nsname ./.;

  ingressClassName = "nginx";
  ingressSecretName = "${domain}-tls";
  secrets = "${instance}-secrets";
  hosts = [domain];
  tls = [
    {
      inherit hosts;
      secretName = ingressSecretName;
    }
  ];
  oauth2Port = 8443;

  pki = "/etc/tls";
  crt = "${pki}/tls.crt";
  key = "${pki}/tls.key";
  ca = "${pki}/ca.crt";

  file = path: "$__file{${path}}";
in {
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
      annotations = {
        # TLS
        "cert-manager.io/cluster-issuer" = "letsencrypt";
        # Ingress
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS";
        "nginx.ingress.kubernetes.io/proxy-ssl-name" = fullName;
        "nginx.ingress.kubernetes.io/proxy-ssl-secret" = "${namespace}/${secretName}";
        "nginx.ingress.kubernetes.io/proxy-ssl-verify" = "on";
        # Homepage
        "gethomepage.dev/enabled" = "true";
        "gethomepage.dev/name" = "Grafana";
        "gethomepage.dev/description" = "Observability platform";
        "gethomepage.dev/group" = "Cluster Management";
        "gethomepage.dev/icon" = "${name}.svg";
        "gethomepage.dev/pod-selector" =
          concatStringsSep ","
          (attrValues (mapAttrs (key: val: "app.kubernetes.io/${key}=${val}") {inherit name instance;}));
      };
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
        cert_file = crt;
        cert_key = key;

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
        client_secret = file "/etc/secrets/oauth2-client-secret";
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
          subPath = "ca.crt";
          readOnly = true;
        }
        {
          name = "certs";
          mountPath = "/etc/ssl/certs";
        }
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

      secureJsonData = {
        tlsCACert = file ca;
        tlsClientCert = file crt;
        tlsClientKey = file key;
      };
      version = 1;
    in [
      {
        inherit secureJsonData version;
        name = "Prometheus";
        type = prometheus;
        uid = prometheus;
        editable = false;
        url = "https://${instance}-${prometheus}:9090/${prometheus}";
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
      exec.command = [
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

    extraSecretMounts = map (mount: mount // {readOnly = true;}) [
      rec {
        name = "secrets";
        mountPath = "/etc/${name}";
        secretName = "${instance}-${name}";
      }
      {
        name = "tls";
        mountPath = pki;
        inherit secretName;
      }
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
          key = "tls.crt";
        };
        keySecret = {
          name = secretName;
          key = "tls.key";
        };
        client_ca.secret = {
          name = secretName;
          key = "ca.crt";
        };
        serverName = fullName;
      };
    };
  };

  prometheus = let
    name = "prometheus";
    fullName = "${instance}-${name}";
    path = "/${name}";
    secretName = "${name}-tls";
    ingressSecretMount = "secret-${replaceStrings ["."] ["-"] ingressSecretName}";
  in rec {
    ingress = {
      inherit hosts ingressClassName tls;

      enabled = true;
      paths = [path];
      pathType = "ImplementationSpecific";
      annotations = {
        # TLS
        "cert-manager.io/cluster-issuer" = "letsencrypt";
        # Ingress
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS";
        "nginx.ingress.kubernetes.io/proxy-ssl-name" = fullName;
        "nginx.ingress.kubernetes.io/proxy-ssl-secret" = "${namespace}/${secretName}";
        "nginx.ingress.kubernetes.io/proxy-ssl-verify" = "on";
        # NGINX: Increase header size since auth cookies are way too large.
        "nginx.ingress.kubernetes.io/proxy-buffer-size" = "16k";
        "nginx.ingress.kubernetes.io/proxy-buffers" = "8 16k";
        # Homepage
        "gethomepage.dev/enabled" = "true";
        "gethomepage.dev/name" = "Prometheus";
        "gethomepage.dev/description" = "Monitoring system";
        "gethomepage.dev/group" = "Cluster Management";
        "gethomepage.dev/icon" = "${name}.svg";
        "gethomepage.dev/pod-selector" =
          concatStringsSep ","
          (attrValues (mapAttrs (key: val: "app.kubernetes.io/${key}=${val}") {inherit name instance;}));
      };
    };

    service = {
      port = oauth2Port;
      targetPort = oauth2Port;
      additionalPorts = [
        rec {
          name = "http-web";
          port = 9090;
          targetPort = port;
          appProtocol = "https";
        }
      ];
    };

    prometheusSpec = {
      retention = "28d";
      routePrefix = path; # should not be necessary
      externalUrl = "https://${domain}${path}";

      # The default port (service.port) is directed to the oauth2-proxy port.
      # An additional port is created with the name http-web pointing to the internal port (9090).
      portName = "oauth2-proxy";

      web.tlsConfig = {
        cert.secret = {
          name = secretName;
          key = "tls.crt";
        };
        keySecret = {
          name = secretName;
          key = "tls.key";
        };
        client_ca.secret = {
          name = secretName;
          key = "ca.crt";
        };
        # NOTE: RequireAndVerifyClientCert causes startup probes to fail.
        clientAuthType = "VerifyClientCertIfGiven";

        storageSpec.emptyDir.medium = "Memory";
      };
      containers = let
        configFile = "oauth2_proxy.conf";
        configPath = "/etc/${configFile}";
      in [
        {
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
          # Loading files from /etc/prometheus doesn't seem to work.
          # Maybe because of the multiple levels of symbolic links, who knows, but avoiding symlinks seems to work.
          volumeMounts = [
            {
              name = "configmap-${instance}-oauth-config";
              mountPath = configPath;
              subPath = name;
              readOnly = true;
            }
            {
              name = "secret-${secretName}";
              mountPath = "/etc/tls";
              readOnly = true;
            }
            {
              name = ingressSecretMount;
              mountPath = "/etc/ssl/ingress.crt";
              subPath = "tls.crt";
              readOnly = true;
            }
            {
              name = "certs";
              mountPath = "/etc/ssl/certs";
            }
          ];
          securityContext = {
            allowPrivilegeEscalation = false;
            capabilities.drop = ["ALL"];
            readOnlyRootFilesystem = true;
          };
        }
      ];
      initContainers = [
        {
          name = "update-ca-certificates";
          image = "busybox:${v.busybox.docker}";
          args = [
            "sh"
            "-c"
            # Running update-ca-certificates wold be nicer, but this works too.
            ''cat /etc/ssl/ingress.crt /etc/tls/ca.crt > /etc/ssl/certs/ca-certificates.crt''
          ];
          resources = rec {
            limits = {
              cpu = "50m";
              memory = "64Mi";
              ephemeral-storage = "64Mi";
            };
            requests = limits;
          };
          volumeMounts = [
            {
              name = "secret-${secretName}";
              mountPath = "/etc/tls";
              readOnly = true;
            }
            {
              name = ingressSecretMount;
              mountPath = "/etc/ssl/ingress.crt";
              subPath = "tls.crt";
              readOnly = true;
            }
            {
              name = "certs";
              mountPath = "/etc/ssl/certs";
            }
          ];
          securityContext = {
            allowPrivilegeEscalation = false;
            capabilities.drop = ["ALL"];
            readOnlyRootFilesystem = true;
          };
        }
      ];

      secrets = [secretName ingressSecretName];
      configMaps = ["${instance}-oauth-config"];
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
        inherit (prometheusSpec.web.tlsConfig) cert keySecret client_ca;
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
        metadata.name = "${instance}-oauth-config";
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
          tls_cert_file = "${crt}"
          tls_key_file = "${key}"

          cookie_secure = "true"
          cookie_samesite = "strict"
          cookie_name = "__Host-${name}"

          upstreams = ["https://localhost:9090"]

          skip_provider_button = "true"
        '';
      })
    ];
}
