{
  pkgs,
  self,
  inputs',
  ...
}: let
  inherit (pkgs) lib;
  inherit (self.lib) cluster;

  talosctl = import ../../talosctl.nix pkgs;

  silent = true;
  state = "$DEVENV_STATE/talos";
  writeShellApplication = inputs: let
    name = "talos-task";
    params = inputs // {inherit name;};
  in "${pkgs.writeShellApplication params}/bin/${name}";
in {
  version = 3;

  tasks = let
    checkVar = name: command: {
      sh = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubernetes-helm];
        text = ''
          test -f "''$${name}"
        '';
      };
      msg = "Missing ${name}! To fix it, run: task talos:${command}";
    };
    helmInstall = name: let
      inherit (builtins) elemAt;
      inherit (release.spec.chart.spec) chart;
      inherit (release.spec.chart.spec) version;

      namespace = "kube-system";
      release = import ../../../manifests/${namespace}/${name}/app/helm-release.yaml.nix {
        inherit cluster;
        k = self.lib.kubernetes;
        v = cluster.versions;
      };
      repo = release.spec.chart.spec.sourceRef.name;
      repoUrl = elemAt cluster.versions-data.${name}.helm 0;
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
            [ "$installed_version" = "${version}" ]
          '';
        })
      ];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubernetes-helm];
        text = ''
          echo "Installing Helm release ${name} version ${version} in namespace ${namespace}, stand by…"
          helm repo add "${repo}" "${repoUrl}"
          helm repo update "${repo}"
          helm install "${name}" "${repo}/${chart}" \
            --namespace="${namespace}" \
            --values="$MANIFESTS/${namespace}/${name}/app/values.yaml" \
            --version="${version}"
        '';
      };
      preconditions = [have-kubeconfig];
    };
    waitForNodes = ready: {
      inherit silent;
      desc = "Wait for nodes${
        if ready
        then " to become ready"
        else ""
      }";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils kubectl];
        text = ''
          echo "Waiting for nodes…"
          until kubectl wait --for=condition=Ready=${
            if ready
            then "true"
            else "false"
          } nodes --all --timeout=120s; do
            echo "Still waiting for nodes…"
            sleep 2
          done
        '';
      };
    };

    have-kubeconfig = checkVar "KUBECONFIG" "fetch-kubeconfig";
    have-talosconfig = checkVar "TALOSCONFIG" "genconfig";
    have-talsecret = checkVar "TALSECRET" "gensecret";
  in {
    bootstrap = {
      inherit silent;
      desc = "Bootstrap Talos cluster";
      cmds = map (task: {inherit task;}) [
        "gensecret"
        "genconfig"
        "ping"
        "apply-insecure"
        "install-k8s"
        "fetch-kubeconfig"
        # CNI is disabled, nodes will not be ready yet.
        "wait-for-nodes"
        "install-cilium"
        "install-kubelet-csr-approver"
        "wait-for-cilium"
        # CNI is installed, nodes should become ready now.
        "wait-for-nodes-ready"
        "wait-for-cluster-health"
      ];
    };

    gensecret = {
      inherit silent;
      desc = "Generate Talos secrets";
      status = [have-talsecret.sh];
      cmds = [
        {
          cmd = writeShellApplication {
            runtimeInputs = [inputs'.talhelper.packages.default];
            text = ''
              talhelper gensecret > "$TALSECRET"
            '';
          };
        }
        {
          task = ":sops:encrypt-file";
          vars.file = "$TALSECRET";
        }
      ];
    };

    genconfig = {
      inherit silent;
      desc = "Generate Talos configs";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [coreutils inputs'.talhelper.packages.default];
        text = ''
          rm -rf "${state}"/*.yaml
          echo "Generating Talos config…"
          talhelper genconfig --config-file="$TALCONFIG" --secret-file="$TALSECRET" --out-dir="${state}"
        '';
      };
      preconditions = [have-talsecret];
    };

    apply-insecure = {
      inherit silent;
      desc = "Apply initial cluster config";
      cmd = {
        task = "apply";
        vars.extra_flags = "--insecure";
      };
    };

    install-k8s = {
      inherit silent;
      desc = "Bootstrap Kubernetes on Talos nodes";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [bash coreutils inputs'.talhelper.packages.default];
        text = ''
          echo "Installing Kubernetes, this might take a while…"
          until talhelper gencommand bootstrap --config-file="$TALCONFIG" --out-dir="${state}" |
            bash
            do sleep 20
            echo Retrying…
          done
        '';
      };
      preconditions = [have-talosconfig];
    };

    fetch-kubeconfig = {
      inherit silent;
      desc = "Fetch Talos Kubernetes kubeconfig file";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [bash coreutils inputs'.talhelper.packages.default];
        text = ''
          echo "Fetching kubeconfig…"
          until talhelper gencommand kubeconfig --config-file="$TALCONFIG" --out-dir="${state}" \
            --extra-flags="--merge=false --force $KUBECONFIG" |
            bash
            do sleep 2
            echo Retrying…
          done
        '';
      };
      preconditions = [have-talosconfig];
    };

    install-cilium = helmInstall "cilium";
    install-kubelet-csr-approver = helmInstall "kubelet-csr-approver";

    wait-for-nodes = waitForNodes false;
    wait-for-nodes-ready = waitForNodes true;
    wait-for-cilium = {
      inherit silent;
      desc = "Wait for Cilium to become ready";
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [cilium-cli coreutils];
        text = ''
          cilium status --wait --wait-duration=30m
        '';
      };

      preconditions = [have-kubeconfig];
    };
    wait-for-cluster-health = {
      inherit silent;
      desc = "Wait for Talos cluster to become healthy";
      cmd = writeShellApplication {
        runtimeInputs = [talosctl];
        text = ''
          talosctl health --server=false
        '';
      };

      preconditions = [have-talosconfig];
    };

    apply = {
      inherit silent;
      desc = "Apply Talos config to all nodes";
      cmd = let
        cmd = writeShellApplication {
          runtimeInputs = with pkgs; [bash coreutils inputs'.talhelper.packages.default];
          text = ''
            extra_flags="$1"

            echo "Applying Talos config to all nodes…"
            talhelper gencommand apply --config-file="$TALCONFIG" --out-dir="${state}" --extra-flags="$extra_flags" |
              bash
          '';
        };
      in ''"${cmd}" "{{.extra_flags}}"'';
      preconditions = [have-talosconfig];
    };

    diff = {
      inherit silent;
      desc = "Diff Talos config on all nodes";
      cmd = {
        task = "apply";
        vars.extra_flags = "--dry-run";
      };
      preconditions = [have-talosconfig];
    };

    ping = {
      inherit silent;
      desc = "Ping Talos nodes matching the pattern in nodes=";
      cmd = let
        cmd = writeShellApplication {
          runtimeInputs = with pkgs; [findutils iputils yq];
          text = ''
            nodes="$1"
            cli_args=("''${@:2}")

            yq < "$TALCONFIG" '.nodes[] | select(.hostname | test("^.*'"$nodes"'.*$")) | .ipAddress' |
              xargs -i ping -c 1 {} "''${cli_args[@]}"
          '';
        };
      in ''"${cmd}" "{{.nodes}}" {{.CLI_ARGS}}'';
    };

    create-join-token = {
      inherit silent;
      desc = "Create Kubernetes join token for non-Talos workers to join";
      cmd = let
        cmd = writeShellApplication {
          runtimeInputs = with pkgs; [coreutils gzip kubectl yq];
          text = ''
            ca="$(
              kubectl get configmap kube-root-ca.crt -o jsonpath='{.data}' \
                --namespace=kube-system |
                jq -r '.["ca.crt"]'
            )"
            bootstrap_token="$(
              kubectl get secret -o yaml \
                --namespace=kube-system \
                --field-selector=type=bootstrap.kubernetes.io/token -o yaml |
                yq -r '
                  [
                    .items |
                    sort_by(.metadata.creationTimestamp) |
                    reverse |
                    .[] |
                    select(.type=="bootstrap.kubernetes.io/token")
                  ] |
                  first |
                  .data
                '
            )"
            join_token="$(
              echo "$bootstrap_token" |
                jq -r '.["token-id"]' |
                base64 -d
            ).$(
              echo "$bootstrap_token" |
                jq -r '.["token-secret"]' |
                base64 -d
            )"
            bootstrap_config_yaml="\
            apiVersion: v1
            kind: Config
            clusters:
            - name: k0s
              cluster:
                certificate-authority-data: $(echo "$ca" | base64 -w0)
                server: https://${(builtins.head cluster.nodes.by.controlPlane).ipv4}:6443
            contexts:
            - name: k0s
              context:
                cluster: k0s
                user: kubelet-bootstrap
            current-context: k0s
            preferences: {}
            users:
            - name: kubelet-bootstrap
              user:
                token: $join_token"

            echo "$bootstrap_config_yaml" |
              gzip -9 |
              base64 -w0
          '';
        };
      in ''"${cmd}" "{{.nodes}}" {{.CLI_ARGS}}'';
    };

    upgrade-talos = let
      variables = ''
        node="$1"
        ip="$(
          yq -r < "$TALCONFIG" '
            .nodes[] |
            select(.hostname == "'"$node"'") |
            .ipAddress
          '
        )"
        image="$(
          yq -r < "${state}/${cluster.name}-$node.yaml" \
            .machine.install.image |
          head --lines=1
        )"
      '';
    in {
      inherit silent;
      desc = "Upgrade Talos on a node";
      requires.vars = ["node"];
      status = let
        cmd = writeShellApplication {
          runtimeInputs = with pkgs; [gnugrep jq talosctl yq];
          text = ''
            ${variables}
            tag="''${image##*:}"

            talosctl version --nodes="$ip" --json |
              jq -r .version.tag |
              grep "$tag"
          '';
        };
      in [''"${cmd}" "{{.node}}"''];
      cmd = let
        cmd = writeShellApplication {
          runtimeInputs = with pkgs; [coreutils talosctl yq];
          text = ''
            ${variables}

            talosctl upgrade --nodes="$ip" --image="$image" --preserve=true --reboot-mode=powercycle
          '';
        };
      in ''"${cmd}" "{{.node}}"'';
      preconditions = [have-talosconfig];
    };

    upgrade-k8s = {
      inherit silent;
      desc = "Upgrade Kubernetes on a node";
      requires.vars = ["node" "version"];
      status = let
        cmd = writeShellApplication {
          runtimeInputs = with pkgs; [jq gnugrep kubectl];
          text = ''
            node="$1"
            version="$2"

            kubectl get node -ojson |
              jq -r '.items[] | select(.metadata.name == "'"$node"'").status.nodeInfo.kubeletVersion' |
              grep "v$version"
          '';
        };
      in [''"${cmd}" "{{.node}}" "{{.version}}"''];
      cmd = let
        cmd = writeShellApplication {
          runtimeInputs = [talosctl];
          text = ''
            node="$1"
            version="$2"

            talosctl upgrade-k8s --nodes="$node" --to=v"$version"
          '';
        };
      in ''"${cmd}" "{{.node}}" "{{.version}}"'';
      preconditions = [have-talosconfig have-kubeconfig];
    };

    reset = {
      inherit silent;
      desc = "Resets Talos nodes back to maintenance mode";
      prompt = "DANGER ZONE!!! Are you sure? This will reset the nodes back to maintenance mode.";
      cmd = let
        flags = lib.strings.concatStringsSep " " [
          "--reboot"
          "--system-labels-to-wipe=STATE"
          "--system-labels-to-wipe=EPHEMERAL"
          "--graceful=false"
          "--wait=false"
        ];
      in
        writeShellApplication {
          runtimeInputs = with pkgs; [bash inputs'.talhelper.packages.default];
          text = ''
            talhelper gencommand reset --config-file="$TALCONFIG" --out-dir="${state}" --extra-flags="${flags}" |
              bash
          '';
        };
      preconditions = [have-talosconfig];
    };
  };
}
