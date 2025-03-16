{
  pkgs,
  self,
  ...
}: let
  inherit (self.lib) cluster;

  silent = true;
  manifests = "$DEVENV_STATE/manifests";
  writeShellApplication = inputs: let
    name = "flux-task";
    params = inputs // {inherit name;};
  in "${pkgs.writeShellApplication params}/bin/${name}";
in {
  version = 3;

  tasks = {
    bootstrap = {
      inherit silent;
      desc = "Install Flux (using flux-operator)";
      cmds = map (task: {inherit task;}) [
        "install-operator"
        "create-flux-instance"
        "check" # reconcile won't work yet
        "install-external-secrets"
        "create-secret"
        "create-cluster-secret-store"
        "create-external-secret"
        "reconcile"
      ];
    };

    build = {
      inherit silent;
      desc = "OCI image build + unpack locally";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils findutils nix];
        text = ''
          cd "$DEVENV_ROOT"
          rm --recursive --force "${manifests}"
          nix build --print-out-paths |
            xargs -I{} cp --recursive {} "${manifests}"
          chmod +w --recursive "${manifests}"
        '';
      };
    };

    diff = {
      inherit silent;
      desc = "OCI image build + unpack + diff locally";
      cmds = [
        {task = "build";}
        (writeShellApplication {
          runtimeInputs = with pkgs; [fluxcd];
          text = ''
            flux diff kustomization flux-system \
              --local-sources=OCIRepository/flux-system/flux-system="${manifests}" \
              --path="${manifests}" \
              --recursive
          '';
        })
      ];
    };

    push = {
      inherit silent;
      desc = "Upload OCI image to the registry";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils nix];
        text = ''
          cd "$DEVENV_ROOT"
          nix run "#deploy"
        '';
      };
    };

    reconcile = {
      inherit silent;
      desc = "Reconcile Flux manifests";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils nix];
        text = ''
          flux reconcile ks flux-system --with-source
        '';
      };
    };

    check = {
      inherit silent;
      desc = "Check Flux installation";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils findutils nix];
        text = ''
          flux check
        '';
      };
    };

    install-operator = let
      inherit (builtins) elemAt;

      name = "flux-operator";
      namespace = "flux-system";
      chart = name;
      repoUrl = elemAt cluster.versions-data.${name}.helm 0;
      version = cluster.versions.${name}.helm;
    in {
      inherit silent;
      desc = "Install Helm release ${name}";
      status = [
        (writeShellApplication {
          runtimeInputs = with pkgs; [kubernetes-helm yq];
          text = ''
            installed_version=$(
              helm list -n "${namespace}" -o yaml |
                yq '.[] | select(.name == "${name}") | .app_version' -r
            )
            [ "$installed_version" = "v${version}" ]
          '';
        })
      ];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubernetes-helm];
        text = ''
          echo "Installing Helm release ${name} version ${version} in namespace ${namespace}, stand by…"
          helm install "${name}" "${repoUrl}/${chart}" \
            --create-namespace \
            --namespace="${namespace}" \
            --version="${version}"
        '';
      };
    };

    create-flux-instance = let
      name = "flux";
      namespace = "flux-system";
    in {
      inherit silent;
      desc = "Install Flux instance ${namespace}/${name}";
      status = [
        (writeShellApplication {
          runtimeInputs = with pkgs; [kubectl];
          text = ''
            kubectl get fluxinstance "${name}" \
              --namespace="${namespace}"
          '';
        })
      ];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [kubectl];
        text = ''
          kubectl apply \
            --namespace="${namespace}" \
            --filename="$MANIFESTS/flux-system/flux-instance.yaml"
        '';
      };
    };

    install-external-secrets = let
      inherit (builtins) elemAt;
      inherit (release.spec.chart.spec) chart;
      inherit (release.spec.chart.spec) version;

      name = "external-secrets";
      namespace = "kube-system";
      release = import ../../../manifests/${namespace}/${name}/app/helm-release.yaml.nix {
        k = self.lib.kubernetes;
      };
      repo = release.spec.chart.spec.sourceRef.name;
      repoUrl = elemAt cluster.versions-data.${name}.helm 0;
    in {
      inherit silent;
      desc = "Install External Secrets operator & bootstrap the cluster secret store";
      status = [
        (writeShellApplication {
          runtimeInputs = with pkgs; [kubernetes-helm yq];
          text = ''
            installed_version=$(
              helm list -n "${namespace}" -o yaml |
                yq '.[] | select(.name == "${name}") | .app_version' -r
            )
            [ "$installed_version" = "v${version}" ]
          '';
        })
      ];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubectl kubernetes-helm sops];
        text = ''
          echo "Installing Helm release ${name} version ${version} in namespace ${namespace}, stand by…"
          helm repo add "${repo}" "${repoUrl}"
          helm repo update "${repo}"
          helm install "${name}" "${repo}/${chart}" \
            --namespace="${namespace}" \
            --version="${version}"
        '';
      };
    };

    create-secret = let
      name = "external-secrets";
      namespace = "kube-system";
      kss = import ../../../manifests/${namespace}/${name}/config/cluster-secret-store.yaml.nix {
        k = self.lib.kubernetes;
      };
      secret = kss.spec.provider.gcpsm.auth.secretRef.secretAccessKeySecretRef;
    in {
      inherit silent;
      desc = "Create ClusterSecretStore secret";
      status = [
        (writeShellApplication {
          runtimeInputs = with pkgs; [kubectl];
          text = ''
            kubectl get secret "${secret.name}" \
              --namespace="${secret.namespace}"
          '';
        })
      ];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubectl];
        text = ''
          echo "Decoding GCP service account key…"
          service_account_key="$(
            sops --decrypt "$DEVENV_ROOT/manifests/${namespace}/${name}/config/${secret.name}.sops.json" |
              jq --compact-output .
          )"
          echo "Storing GCP service account in Kubernetes secret ${secret.namespace}/${secret.name}"
          kubectl create secret generic "${secret.name}" \
            --namespace="${secret.namespace}" \
            --from-literal="${secret.key}"="$service_account_key"
        '';
      };
    };

    create-cluster-secret-store = let
      name = "external-secrets";
      namespace = "kube-system";
      kss = import ../../../manifests/${namespace}/${name}/config/cluster-secret-store.yaml.nix {
        k = self.lib.kubernetes;
      };
    in {
      inherit silent;
      desc = "Create ClusterSecretStore object";
      status = [
        (writeShellApplication {
          runtimeInputs = with pkgs; [kubectl];
          text = ''
            kubectl get clustersecretstore "${kss.metadata.name}" \
              --namespace="${namespace}"
          '';
        })
      ];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubectl];
        text = ''
          echo "Creating ClusterSecretStore object…"
          kubectl apply \
            --namespace="${namespace}" \
            --filename="$MANIFESTS/${namespace}/${name}/config/cluster-secret-store.yaml"
        '';
      };
    };

    create-external-secret = let
      namespace = "flux-system";
      es = import ../../../manifests/${namespace}/external-secret.yaml.nix {
        inherit cluster;
        inherit (self) lib;
        k = self.lib.kubernetes;
      };
    in {
      inherit silent;
      desc = "Create ExternalSecret object";
      status = [
        (writeShellApplication {
          runtimeInputs = with pkgs; [kubectl];
          text = ''
            kubectl get externalsecret "${es.metadata.name}" \
              --namespace="${namespace}"
          '';
        })
      ];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubectl];
        text = ''
          echo "Creating ExternalSecret object…"
          kubectl apply \
            --namespace="${namespace}" \
            --filename="$MANIFESTS/${namespace}/external-secret.yaml"
        '';
      };
    };
  };
}
