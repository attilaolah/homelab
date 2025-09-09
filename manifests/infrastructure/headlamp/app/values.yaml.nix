# https://github.com/kubernetes-sigs/headlamp/blob/main/charts/headlamp/values.yaml
{
  cluster,
  k,
  lib,
  self,
  v,
  ...
}: let
  inherit (cluster) domain;
  inherit (lib.strings) concatStringsSep;
  inherit (self.lib) yaml;
  name = k.appname ./.;

  tmp = {
    name = "tmp";
    emptyDir = {};
  };
in {
  inherit (k.container) securityContext;
  podSecurityContext = k.pod.securityContext;

  image.tag = v.headlamp.docker;

  volumes = [tmp];
  volumeMounts = [
    {
      inherit (tmp) name;
      mountPath = "/tmp";
    }
  ];

  env = [
    {
      name = "OIDC_CLIENT_ID";
      value = "kubernetes";
    }
    {
      name = "OIDC_ISSUER_URL";
      value = "https://${domain}/keycloak/realms/dh";
    }
    {
      name = "OIDC_SCOPES";
      # Headlamp will request the mandatory "openid" scope by default:
      # https://headlamp.dev/docs/latest/installation/in-cluster/oidc/#scopes
      value = concatStringsSep "," [
        "email"
        "profile"
      ];
    }
  ];

  ingress = {
    enabled = true;
    ingressClassName = "nginx";
    hosts = [
      {
        host = domain;
        paths = [
          {
            path = "/${name}";
            type = "Prefix";
          }
        ];
      }
    ];
    annotations = with k.annotations;
      cert-manager
      // (homepage {
        name = "Headlamp";
        description = "Extensible Kubernetes UI";
        icon = name;
        group = "Cluster Management";
      });

    tls = [
      {
        hosts = [domain];
        secretName = "${domain}-tls";
      }
    ];
  };

  config = {
    baseURL = "/${name}";
    oidc = {
      secret.create = false;
      externalSecret = {
        enabled = true;
        name = "${name}-secrets";
      };
    };
  };

  resources = let
    requests = {
      cpu = "200m";
      memory = "256Mi";
      ephemeral-storage = "1Gi";
    };
  in {
    inherit requests;
    limits = requests // {cpu = "1";};
  };

  extraManifests = map yaml.format (let
    inherit (builtins) attrValues mapAttrs;
    role = "${name}-ro";
    subjects = [
      {
        kind = "User";
        apiGroup = "rbac.authorization.k8s.io";
        # NOTE: Maybe it would be neat to configure usernames instead of emails here.
        name = "attila@${domain}";
      }
    ];
  in [
    # External secret holding the OIDC Client secret:
    (k.external-secret ./. {
      data.OIDC_CLIENT_SECRET = "{{`{{ .headlamp_client_secret }}`}}";
    })
    # Additional ingress to redirect /headlamp to /headlamp/ including the trailing slash:
    # (k.api "Ingress.networking.k8s.io" {
    #   metadata = {
    #     name = "${name}-redirect";
    #     annotations = with k.annotations;
    #       group "nginx.ingress.kubernetes.io" {
    #         permanent-redirect = "https://${domain}/${name}/";
    #       };
    #   };
    #   spec = {
    #     ingressClassName = "nginx";
    #     rules = [
    #       {
    #         host = domain;
    #         http.paths = [
    #           {
    #             path = "/${name}";
    #             pathType = "Exact";
    #             backend.service = {
    #               inherit name;
    #               port.name = "http";
    #             };
    #           }
    #         ];
    #       }
    #     ];
    #   };
    # })
    # RBAC basic access role:
    (k.api "ClusterRole.rbac.authorization.k8s.io" {
      metadata = {inherit name;};
      rules = attrValues (mapAttrs (group: resources: {
          inherit resources;
          apiGroups = [group];
          verbs = ["create"];
        }) {
          # For OIDC authentication validation:
          "authentication.k8s.io" = [
            "tokenreviews"
            "subjectaccessreviews"
          ];
          # Self-subject access reviews, needed to check permissions:
          "authorization.k8s.io" = [
            "selfsubjectaccessreviews"
            "selfsubjectrulesreviews"
          ];
        });
    })
    # RBAC read-only role:
    (k.api "ClusterRole.rbac.authorization.k8s.io" {
      metadata.name = role;
      rules = attrValues (mapAttrs (group: resources: {
          inherit resources;
          apiGroups = [group];
          verbs = ["get" "list" "watch"];
        }) {
          # No group:
          "" = [
            "configmaps"
            "endpoints"
            "events"
            "namespaces"
            "nodes"
            "persistentvolumeclaims"
            "persistentvolumes"
            "pods"
            "secrets"
            "services"
            "serviceaccounts"
            "limitranges"
            "resourcequotas"
          ];
          # Top-level groups:
          apps = [
            "daemonsets"
            "deployments"
            "replicasets"
            "statefulsets"
          ];
          autoscaling = [
            "horizontalpodautoscalers"
          ];
          batch = [
            "cronjobs"
            "jobs"
          ];
          policy = [
            "poddisruptionbudgets"
          ];
          # Various k8s.io groups:
          "admissionregistration.k8s.io" = [
            "mutatingwebhookconfigurations"
            "validatingwebhookconfigurations"
          ];
          "apiextensions.k8s.io" = [
            "customresourcedefinitions"
          ];
          "autoscaling.k8s.io" = [
            "verticalpodautoscalercheckpoints"
            "verticalpodautoscalers"
          ];
          "coordination.k8s.io" = [
            "leases"
          ];
          "gateway.networking.k8s.io" = [
            "backendtlspolicies"
            "gatewayclasses"
            "gateways"
            "grpcroutes"
            "httproutes"
            "referencegrants"
          ];
          "metrics.k8s.io" = [
            "nodes"
            "pods"
          ];
          "networking.k8s.io" = [
            "ingressclasses"
            "ingresses"
            "networkpolicies"
          ];
          "node.k8s.io" = [
            "runtimeclasses"
          ];
          "rbac.authorization.k8s.io" = [
            "clusterrolebindings"
            "clusterroles"
            "rolebindings"
            "roles"
          ];
          "scheduling.k8s.io" = [
            "priorityclasses"
          ];
          "snapshot.storage.k8s.io" = [
            "volumesnapshotclasses"
            "volumesnapshotcontents"
            "volumesnapshots"
          ];
          "storage.k8s.io" = [
            "storageclasses"
          ];
          "topology.node.k8s.io" = [
            "noderesourcetopologies"
          ];
          # Various k8s-sigs or x-k8s groups:
          "nfd.k8s-sigs.io" = [
            "nodefeaturegroups"
            "nodefeaturerules"
            "nodefeatures"
          ];
          "gateway.networking.x-k8s.io" = [
            "xbackendtrafficpolicies"
          ];
          # Everything else goes below.
          # TODO: Figure out a way to keep this list up-to-date.
          "acme.cert-manager.io" = [
            "challenges"
            "orders"
          ];
          "cert-manager.io" = [
            "certificaterequests"
            "certificates"
            "clusterissuers"
            "issuers"
          ];
          "cilium.io" = [
            "ciliumcidrgroups"
            "ciliumclusterwidenetworkpolicies"
            "ciliumendpoints"
            "ciliumexternalworkloads"
            "ciliumidentities"
            "ciliuml2announcementpolicies"
            "ciliumloadbalancerippools"
            "ciliumlocalredirectpolicies"
            "ciliumnetworkpolicies"
            "ciliumnodeconfigs"
            "ciliumnodes"
            "ciliumpodippools"
          ];
          "external-secrets.io" = [
            "clusterexternalsecrets"
            "clusterpushsecrets"
            "clustersecretstores"
            "externalsecrets"
            "pushsecrets"
            "secretstores"
          ];
          "fluxcd.controlplane.io" = [
            "fluxinstances"
            "fluxreports"
            "resourcesetinputproviders"
            "resourcesets"
          ];
          "generators.external-secrets.io" = [
            "accesstokens"
            "acraccesstokens"
            "clustergenerators"
            "ecrauthorizationtokens"
            "fakes"
            "gcraccesstokens"
            "generatorstates"
            "githubaccesstokens"
            "grafanas"
            "mfas"
            "passwords"
            "quayaccesstokens"
            "sshkeys"
            "stssessiontokens"
            "uuids"
            "vaultdynamicsecrets"
            "webhooks"
          ];
          "helm.toolkit.fluxcd.io" = [
            "helmreleases"
          ];
          "kustomize.toolkit.fluxcd.io" = [
            "kustomizations"
          ];
          "monitoring.coreos.com" = [
            "alertmanagerconfigs"
            "alertmanagers"
            "podmonitors"
            "probes"
            "prometheusagents"
            "prometheuses"
            "prometheusrules"
            "scrapeconfigs"
            "servicemonitors"
            "thanosrulers"
          ];
          "nfd.kubernetes.io" = [
            "nodefeaturediscoveries"
          ];
          "notification.toolkit.fluxcd.io" = [
            "alerts"
            "providers"
            "receivers"
          ];
          "postgresql.cnpg.io" = [
            "backups"
            "clusterimagecatalogs"
            "clusters"
            "databases"
            "failoverquorums"
            "imagecatalogs"
            "poolers"
            "publications"
            "scheduledbackups"
            "subscriptions"
          ];
          "source.toolkit.fluxcd.io" = [
            "buckets"
            "gitrepositories"
            "helmcharts"
            "helmrepositories"
            "ocirepositories"
          ];
          "zfs.openebs.io" = [
            "zfsbackups"
            "zfsnodes"
            "zfsrestores"
            "zfssnapshots"
            "zfsvolumes"
          ];
        });
    })
    # RBAC binding assigning both roles to admin users:
    (k.api "ClusterRoleBinding.rbac.authorization.k8s.io" {
      inherit subjects;
      metadata = {inherit name;};
      roleRef = {
        inherit name;
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
      };
    })
    (k.api "ClusterRoleBinding.rbac.authorization.k8s.io" {
      inherit subjects;
      metadata.name = role;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = role;
      };
    })
  ]);
}
