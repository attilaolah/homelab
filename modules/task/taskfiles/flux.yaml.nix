{
  pkgs,
  self,
  ...
}: let
  inherit (self.lib) cluster;

  silent = true;
  manifests = "$DEVENV_STATE/manifests";
  writeShellApplication = config @ {name, ...}: "${pkgs.writeShellApplication config}/bin/${name}";
in {
  version = 3;

  tasks = {
    build = {
      inherit silent;
      desc = "OCI image build + unpack locally";
      cmd = writeShellApplication {
        name = "flux-build";
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
          name = "flux-diff";
          runtimeInputs = with pkgs; [fluxcd];
          text = ''
            flux diff kustomization flux-system \
              --local-sources=OCIRepository/flux-system/flux-system=${manifests} \
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
        name = "flux-push";
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
        name = "flux-reconcile";
        runtimeInputs = with pkgs; [coreutils nix];
        text = ''
          flux reconcile ks flux-system --with-source
        '';
      };
    };

    install = {
      inherit silent;
      desc = "Install Flux (using flux-operator)";
      cmds = [
        {task = "install-operator";}
        {task = "install-instance";}
      ];
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
          name = "helm-install-${name}-status";
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
        name = "helm-install-${name}";
        runtimeInputs = with pkgs; [coreutils kubernetes-helm];
        text = ''
          echo "Installing Helm release ${name} version ${version} in namespace ${namespace}, stand by…"
          helm install "${name}" "${repoUrl}/${chart}" \
            --namespace="${namespace}" --create-namespace \
            --version="${version}"
        '';
      };
    };

    install-instance = let
      name = "flux";
      namespace = "flux-system";
    in {
      inherit silent;
      desc = "Install Flux instance ${namespace}/${name}";
      status = [
        (writeShellApplication {
          name = "helm-install-${name}";
          runtimeInputs = with pkgs; [kubectl];
          text = ''
            kubectl --namespace="${namespace}" get fluxinstance "${name}"
          '';
        })
      ];
      cmd = writeShellApplication {
        name = "helm-install-${name}";
        runtimeInputs = with pkgs; [kubectl];
        text = ''
          kubectl apply --filename="$MANIFESTS/flux-system/flux-instance.yaml"
        '';
      };
    };
  };
}
