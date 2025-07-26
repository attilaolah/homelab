# https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml
{
  cluster,
  k,
  lib,
  v,
  ...
}: let
  inherit (builtins) listToAttrs;
  inherit (cluster) domain;
  inherit (lib.strings) concatStringsSep;

  instance = k.appname ./.;
  namespace = k.nsname ./.;
  group = "Cluster Management";

  origin = "https://${domain}";

  ingressClassName = "nginx";
  ingressSecretName = "${domain}-tls";
  secrets = "${instance}-secrets";

  oap = "oauth2-proxy";
  oaConfig = "${instance}-oauth-config";
  oaComponents = [
    "prometheus"
    "alertmanager"
  ];

  hosts = [domain];
  tls = [
    {
      inherit hosts;
      secretName = ingressSecretName;
    }
  ];

  ports = {
    prometheus = 9090;
    alertmanager = 9093;
    oauth = 8443;
  };

  storage.emptyDir.sizeLimit = "64Gi";

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
  volumes = [
    {
      inherit (certsMount) name;
      emptyDir.medium = "Memory";
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
  securityContext = {
    allowPrivilegeEscalation = false;
    capabilities.drop = ["ALL"];
    readOnlyRootFilesystem = true;
  };

  localFile = path: "$__file{${path}}";

  # Component: Alertmanager / Prometheus.
  containers = component: let
    configFile = "oauth2_proxy.conf";
    configPath = "/etc/${configFile}";
  in [
    {
      inherit resources securityContext;

      name = oap;
      image = "quay.io/${oap}/${oap}:${v.oauth2-proxy.docker}";
      args = ["--config" configPath];
      env = [
        {
          name = "OAUTH2_PROXY_CLIENT_SECRET";
          valueFrom.secretKeyRef = {
            name = secrets;
            key = "oauth2_client_secret";
          };
        }
        {
          name = "OAUTH2_PROXY_COOKIE_SECRET";
          valueFrom.secretKeyRef = {
            name = secrets;
            key = "oauth2_cookie_secret";
          };
        }
      ];
      ports = [
        {
          name = oap;
          containerPort = ports.oauth;
          protocol = "TCP";
        }
      ];
      # Loading files from /etc/prometheus doesn't seem to work.
      # Maybe because of the multiple levels of symbolic links, who knows, but avoiding symlinks seems to work.
      volumeMounts = [
        (k.pki.mount // {name = "secret-${component}-tls";})
        certsMount
        {
          name = "configmap-${oaConfig}";
          mountPath = configPath;
          subPath = component;
          readOnly = true;
        }
      ];
    }
  ];

  initContainers = component: [
    {
      inherit resources securityContext;

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
      volumeMounts = [
        certsMountNew
        {
          name = "secret-${component}-tls";
          mountPath = k.pki.dir;
          readOnly = true;
        }
      ];
    }
  ];
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
      prefix = "${name}_admin";
    in {
      userKey = "${prefix}_user";
      passwordKey = "${prefix}_password";
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
        idp = "${origin}/keycloak/realms/dh/protocol/openid-connect";
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
        client_secret = localFile "/etc/secrets/oauth2_client_secret";
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
          # TODO: Is this still required?
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
        url = "https://${instance}-${prometheus}:${toString ports."${prometheus}"}/${prometheus}";
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
    extraContainerVolumes = volumes;

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
  in rec {
    ingress = {
      inherit hosts ingressClassName tls;

      enabled = true;
      paths = [path];
      pathType = "ImplementationSpecific";
      servicePort = ports.oauth;
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
        name = oap;
        port = ports.oauth;
        targetPort = ports.oauth;
        appProtocol = "https";
      }
    ];

    prometheusSpec = let
    in {
      inherit volumes;

      nodeSelector."feature.node.kubernetes.io/system-os_release.ID" = "talos";

      retention = "28d";
      routePrefix = path;
      externalUrl = "${origin}${path}";

      enableOTLPReceiver = true;
      additionalArgs = [
        {
          name = "web.cors.origin";
          value = origin;
        }
      ];

      storageSpec = storage;

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

      containers = containers name;
      initContainers = initContainers name;

      secrets = [secretName ingressSecretName];
      configMaps = [oaConfig];
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
    [
      (k.api "ConfigMap" {
        metadata.name = oaConfig;
        data = listToAttrs (map (name: {
            inherit name;
            value = ''
              provider = "keycloak-oidc"
              client_id = "monitoring"
              oidc_issuer_url = "${origin}/keycloak/realms/dh"
              redirect_url = "${origin}/${name}/auth/callback"
              code_challenge_method = "S256"
              email_domains = "${domain}"

              reverse_proxy = true
              proxy_prefix = "/${name}/auth"

              https_address = "[::]:${toString ports.oauth}"
              tls_cert_file = "${k.pki.crt}"
              tls_key_file = "${k.pki.key}"

              cookie_secure = "true"
              cookie_samesite = "strict"
              cookie_name = "__Host-${name}"

              upstreams = ["https://localhost:${toString ports."${name}"}"]

              skip_provider_button = "true"
            '';
          })
          oaComponents);
      })
    ]
    ++ (
      map (name:
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
        }) (oaComponents ++ ["grafana"])
    );
}
