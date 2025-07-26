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

  https = host: "https://${host}";
  origin = https domain;
  local = https "localhost";

  ingressClassName = "nginx";
  ingressSecretName = secretName domain;
  secrets = "${instance}-secrets";

  oap = "oauth2-proxy";
  oaConfig = "${instance}-oauth-config";
  oaComponents = [
    "prometheus"
    "alertmanager"
  ];
  oaIngress = {
    pathType = "ImplementationSpecific";
    servicePort = ports.oauth;
  };
  oaService.additionalPorts = [
    {
      name = oap;
      port = ports.oauth;
      targetPort = ports.oauth;
      appProtocol = "https";
    }
  ];

  hosts = [domain];
  ports = {
    grafana = 3000;
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
  secretsMount = "/etc/secrets";
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

  path = component: "/${component}";
  fullName = component: "${instance}-${component}";
  secretName = component: "${component}-tls";
  pretty = {
    grafana = {
      name = "Grafana";
      description = "Observability platform";
    };
    prometheus = {
      name = "Prometheus";
      description = "Metric collection & storage";
    };
    alertmanager = {
      name = "Alertmanager";
      description = "Alerting configuration & dispatch";
    };
    # TOOD: Auto-generate title-case names.
    jaeger.name = "Jaeger";
    loki.name = "Loki";
  };

  ingress = component: {
    inherit hosts ingressClassName;

    enabled = true;
    path = path component; # grafana
    paths = map path [component]; # others
    annotations = with k.annotations;
      cert-manager
      // (ingress-nginx {
        inherit namespace;
        name = fullName component;
        secret = secretName component;
        # Increase header size to fit auth cookies.
        # TODO: Remove when switching to redis oauth backend.
        proxyBufferSize = "16k";
      })
      // (homepage {
        inherit group;
        inherit (pretty."${component}") name description;
        icon = component;
        selector = {
          inherit instance;
          name = component;
        };
      });
    tls = [
      {
        inherit hosts;
        secretName = ingressSecretName;
      }
    ];
  };

  caConfig = component: {
    secret = {
      name = secretName component;
      key = k.pki.files.ca;
    };
  };
  tlsConfig = component: let
    name = secretName component;
  in {
    cert.secret = {
      inherit name;
      key = k.pki.files.crt;
    };
    keySecret = {
      inherit name;
      key = k.pki.files.key;
    };
  };
  tlsClientConfig = component:
    (tlsConfig component)
    // {
      ca = caConfig component;
      serverName = fullName component;
    };
  tlsServerConfig = component:
    (tlsConfig component)
    // {
      client_ca = caConfig component;
      # NOTE: RequireAndVerifyClientCert would be better, but it causes startup probes to fail.
      clientAuthType = "VerifyClientCertIfGiven";
    };

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
        (k.pki.mount // {name = secretName "secret-${component}";})
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
          name = secretName "secret-${component}";
          mountPath = k.pki.dir;
          readOnly = true;
        }
      ];
    }
  ];

  probe = component: {
    exec.command = with k.pki; let
      url = "${local}:${toString ports."${component}"}/api/health";
    in ["curl" "--silent" url "--cert" crt "--key" key "--cacert" ca];
    httpGet = null;
  };

  spec = component: let
    routePrefix = path component;
  in {
    inherit routePrefix volumes;

    externalUrl = "${origin}${routePrefix}";

    web = {tlsConfig = tlsServerConfig component;};

    containers = containers component;
    initContainers = initContainers component;
    configMaps = [oaConfig];
    secrets = [(secretName component) ingressSecretName];
  };

  common = component: {
    ingress = (ingress component) // oaIngress;
    service = oaService;
    serviceMonitor = {
      scheme = "https";
      tlsConfig = tlsClientConfig component;
    };
  };

  localFile = path: "$__file{${path}}";
in {
  # Grafana subchart config defaults:
  # https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
  grafana = let
    component = "grafana";
    port = ports."${component}";
    localAddr = "${local}:${toString port}";
  in {
    ingress = ingress component;

    admin = let
      prefix = "${component}_admin";
    in {
      userKey = "${prefix}_user";
      passwordKey = "${prefix}_password";
      existingSecret = "${instance}-secrets";
    };

    # Grafana's primary configuration.
    "grafana.ini" = {
      server = {
        serve_from_sub_path = true;
        root_url = "${origin}${path component}";
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
        client_secret = localFile "${secretsMount}/oauth2_client_secret";
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

      reload = what: "${localAddr}${path component}/api/admin/provisioning/${what}/reload";
    in {
      dashboards = {
        inherit env extraMounts script;
        reloadURL = reload "dashboards";
      };
      datasources = {
        inherit env extraMounts script;
        reloadURL = reload "datasources";
        # Datasources installed manually below.
        defaultDatasourceEnabled = false;
      };
    };

    additionalDataSources = let
      jsonData = {
        tlsAuth = true;
        tlsAuthWithCACert = true;
      };
      secureJsonData = with k.pki; {
        tlsCACert = localFile ca;
        tlsClientCert = localFile crt;
        tlsClientKey = localFile key;
      };
      version = 1;

      unique = name: {
        inherit secureJsonData version;
        inherit (pretty."${name}") name;
        type = name;
        uid = name;
        editable = false;
        url = "https://${instance}-${name}:${toString ports."${name}"}/${name}";
      };
    in [
      ((unique "prometheus")
        // {
          inherit jsonData;
        })
      ((unique "alertmanager")
        // {
          jsonData =
            jsonData
            // {
              implementation = "prometheus";
              handleGrafanaManagedAlerts = true;
            };
        })
      ((unique "jaeger")
        // {
          url = "https://jaeger-query-https.observability.svc/jaeger";
          jsonData =
            jsonData
            // {
              tracesToMetrics.datasourceUid = "prometheus";
            };
        })
      ((unique "loki")
        // {
          url = "http://loki.observability.svc:3100";
        })
    ];

    livenessProbe = probe component;
    readinessProbe = probe component;

    extraSecretMounts = [
      {
        name = "secrets";
        mountPath = secretsMount;
        secretName = "${instance}-secrets";
        readOnly = true;
      }
      (k.pki.mount // {secretName = secretName component;})
    ];
    extraContainerVolumes = volumes;

    serviceMonitor = {
      path = "${path component}/metrics";
      scheme = "https";
      tlsConfig = tlsClientConfig component;
    };
  };

  # Prometheus subchart config defaults:
  # https://github.com/prometheus-community/helm-charts/blob/main/charts/prometheus/values.yaml
  prometheus = let
    component = "prometheus";
  in
    (common component)
    // {
      prometheusSpec =
        (spec component)
        // {
          retention = "28d";
          enableOTLPReceiver = true;
          additionalArgs = [
            {
              name = "web.cors.origin";
              value = origin;
            }
          ];

          storageSpec = storage;
        };
    };

  # Alertmanager subchart config defaults:
  # https://github.com/prometheus-community/helm-charts/blob/main/charts/alertmanager/values.yaml
  alertmanager = let
    component = "alertmanager";
  in
    (common component)
    // {alertmanagerSpec = (spec component) // {inherit storage;};};

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
              proxy_prefix = "${path name}/auth"

              https_address = "[::]:${toString ports.oauth}"
              tls_cert_file = "${k.pki.crt}"
              tls_key_file = "${k.pki.key}"

              cookie_secure = "true"
              cookie_samesite = "strict"
              cookie_name = "__Host-${name}"

              upstreams = ["${local}:${toString ports."${name}"}"]

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
            secretName = secretName name;
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
