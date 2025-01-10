{
  lib,
  self,
  ...
}: let
  inherit (builtins) attrValues baseNameOf dirOf elem elemAt filter listToAttrs mapAttrs readDir replaceStrings;
  inherit (lib) optionals;
  inherit (lib.attrsets) filterAttrs recursiveUpdate;
  inherit (lib.lists) flatten subtractLists unique;
  inherit (lib.strings) hasPrefix hasSuffix removeSuffix;
  inherit (self.lib) cluster;

  flux.namespace = "flux-system";
  parentDirName = dir: baseNameOf (dirOf dir);
in {
  hostname = dir: "${(parentDirName dir)}.${cluster.domain}";

  namespace = dir: overrides:
    recursiveUpdate {
      kind = "Namespace";
      apiVersion = "v1";
      metadata.name = baseNameOf dir;
    }
    overrides;

  kustomization = dir: overrides:
    recursiveUpdate {
      kind = "Kustomization";
      apiVersion = "kustomize.config.k8s.io/v1beta1";
      resources =
        subtractLists [
          "kustomization.yaml" # exclude self
          "kustomizeconfig.yaml" # configuration
          "values.yaml" # helm chart values
        ] (filter (item: item != null) (attrValues (mapAttrs (
          name: type:
            if type == "directory"
            then "${name}/ks.yaml" # app subdirectory
            else if (hasSuffix ".yaml.nix" name)
            then removeSuffix ".nix" name # non-flux manifest
            else null
        ) (readDir dir))));
      configMapGenerator =
        if ((readDir dir)."values.yaml.nix" or null) == "regular"
        then [
          {
            name = "${parentDirName dir}-values";
            files = ["./values.yaml"];
          }
        ]
        else [];
      configurations = flatten (map (config:
        if ((readDir dir)."${config}.nix" or null) == "regular"
        then ["./${config}"]
        else []) [
        "kustomizeconfig.yaml"
      ]);
    }
    overrides;

  kustomizeconfig = {
    nameReference = [
      {
        kind = "ConfigMap";
        version = "v1";
        fieldSpecs = [
          {
            path = "spec/valuesFrom/name";
            kind = "HelmRelease";
          }
        ];
      }
    ];
  };

  fluxcd = let
    repository-name = url: let
      noprefix = replaceStrings ["https://" "oci://"] ["" ""] url;
      cleanup = replaceStrings ["/" "." "_"] ["-" "-" "-"] noprefix;
    in
      replaceStrings ["--"] ["-"] cleanup;
  in {
    inherit repository-name;

    kustomization = dir: overrides: let
      name = baseNameOf dir;
      namespace = parentDirName dir;
      exists = listToAttrs (map (name: {
        inherit name;
        value = ((readDir dir).${name} or null) == "directory";
      }) ["app" "config"]);
      manifestPath = dir: "./${namespace}/${name}/${dir}";
      template = ksname: spec:
        recursiveUpdate {
          kind = "Kustomization";
          apiVersion = "kustomize.toolkit.fluxcd.io/v1";
          metadata = {
            inherit (flux) namespace;
            name = ksname;
          };
          spec =
            recursiveUpdate {
              targetNamespace = namespace;
              commonMetadata.labels."app.kubernetes.io/name" = name;
              prune = true;
              sourceRef = {
                kind = "OCIRepository";
                name = flux.namespace;
              };
              wait = true;
              interval = "30m";
              retryInterval = "1m";
              timeout = "5m";
            }
            spec;
        }
        overrides;

      app = template name {path = manifestPath "app";};
      config = template "${name}-config" {
        path = manifestPath "config";
        dependsOn = optionals exists.app [app.metadata];
      };
    in
      flatten [
        (optionals exists.app app)
        (optionals exists.config config)
      ];

    git-repository = params:
      attrValues (mapAttrs (name: spec: let
          url = elemAt cluster.versions-data.${name}.github-releases 0;
        in {
          kind = "GitRepository";
          apiVersion = "source.toolkit.fluxcd.io/v1";
          metadata = {
            inherit (flux) namespace;
            name = repository-name url;
          };
          spec = {
            inherit url;
            interval = "1h";
            ref.tag = cluster.versions.${name}.github-releases;
          };
        })
        params);

    helm-repository = let
      filtered = filterAttrs (dep: datasources: (datasources.helm or null) != null) cluster.versions-data;
      repoURLs = map (datasource: elemAt datasource.helm 0) (flatten (attrValues filtered));
      repo = url: {
        kind = "HelmRepository";
        apiVersion = "source.toolkit.fluxcd.io/v1";
        metadata = {
          name = repository-name url;
          inherit (flux) namespace;
        };
        spec =
          {
            inherit url;
            interval = "2h";
          }
          // (
            if hasPrefix "oci://" url
            then {type = "oci";}
            else {}
          );
      };
    in
      map repo (unique repoURLs);

    helm-release = dir: overrides: let
      name = parentDirName dir;
      crds = "CreateReplace";
      pchart = overrides.chart or name;
    in
      recursiveUpdate {
        kind = "HelmRelease";
        apiVersion = "helm.toolkit.fluxcd.io/v2";
        metadata = {inherit name;};
        spec = {
          interval = "30m";
          chart.spec = {
            chart = pchart;
            version = let
              v = cluster.versions.${pchart};
            in
              v.helm or v.github-releases;
            sourceRef = {
              inherit (flux) namespace;
              name = let
                data = cluster.versions-data.${name};
                url = elemAt (data.helm or data.github-releases) 0;
              in
                repository-name url;
              kind = "HelmRepository";
            };
            interval = "12h";
          };
          install = {
            inherit crds;
            remediation.retries = 2;
          };
          upgrade = {
            inherit crds;
            cleanupOnFail = true;
            remediation.retries = 2;
          };
          valuesFrom = let
            names = {
              ConfigMap = "${name}-values";
              Secret = "${name}-secrets";
            };
            has = name: ((readDir dir)."${name}.yaml.nix" or null) == "regular";
            from = kind: {
              inherit kind;
              name = names.${kind};
            };
          in
            flatten [
              (optionals (has "values") (from "ConfigMap"))
              (optionals (has "external-secret") (from "Secret"))
            ];
        };
      }
      (filterAttrs (name: value: !(elem name ["chart" "v"])) overrides);
  };

  external-secret = dir: overrides @ {
    data,
    name ? null,
    ...
  }:
    recursiveUpdate
    rec {
      kind = "ExternalSecret";
      apiVersion = "external-secrets.io/v1beta1";
      metadata.name =
        if name == null
        then "${parentDirName dir}-secrets"
        else name;
      spec = {
        refreshInterval = "2h";
        secretStoreRef = {
          kind = "ClusterSecretStore";
          name = "gcp-secrets";
        };
        target = {
          inherit (metadata) name;
          template = {
            inherit data;
            engineVersion = "v2";
          };
        };
        dataFrom = [{extract.key = "external-secrets";}];
      };
    }
    (filterAttrs (name: value: !(elem name ["data" "name"])) overrides);
}
