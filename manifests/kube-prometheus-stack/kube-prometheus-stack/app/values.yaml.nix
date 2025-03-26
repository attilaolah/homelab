{
  cluster,
  k,
  lib,
  ...
}: let
  inherit (builtins) attrValues mapAttrs;
  inherit (cluster) domain;
  inherit (lib.strings) concatStringsSep;

  instance = k.appname ./.;
  namespace = k.nsname ./.;
  hosts = [domain];
  tls = [
    {
      inherit hosts;
      secretName = "${domain}-tls";
    }
  ];

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
      inherit hosts path tls;

      enabled = true;
      ingressClassName = "nginx";
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
      existingSecret = "${k.appname ./.}-secrets";
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
          # readOnly = false;
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
        serverName = "${instance}-${name}";
      };
    };
  };

  prometheus = let
    name = "prometheus";
    path = "/${name}";
    secretName = "${name}-tls";
  in rec {
    prometheusSpec = {
      retention = "28d";
      routePrefix = path; # should not be necessary
      externalUrl = "https://${domain}${path}";
      additionalArgs = [
        {name = "web.enable-otlp-receiver";}
      ];
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
      };

      storageSpec.emptyDir.medium = "Memory";

      volumes = [
        {
          name = "tls";
          secret = {inherit secretName;};
        }
      ];

      volumeMounts = [
        {
          name = "tls";
          mountPath = pki;
          readOnly = true;
        }
      ];
    };

    # containers: oauth-proxy!
    serviceMonitor = {
      scheme = "https";
      tlsConfig = {
        inherit (prometheusSpec.web.tlsConfig) cert keySecret client_ca;
        serverName = "${instance}-${name}";
      };
    };
  };

  cleanPrometheusOperatorObjectNames = true;

  extraManifests = map (name:
    k.api "Certificate.cert-manager.io" {
      metadata = {inherit name;};
      spec = {
        secretName = "${name}-tls";
        issuerRef = {
          kind = "ClusterIssuer";
          name = "internal-ca";
        };
        commonName = name;
        dnsNames =
          ["${instance}-${name}"]
          # Allow sidecars to connect via the loopback interface:
          ++ lib.optionals (name == "grafana") ["localhost"];
      };
    }) [
    "grafana"
    "prometheus"
    "alertmanager"
  ];
}
