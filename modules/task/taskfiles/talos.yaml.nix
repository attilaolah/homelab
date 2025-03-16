{
  pkgs,
  self,
  inputs',
  ...
}: let
  inherit (pkgs) lib;
  inherit (lib) getExe getExe';
  inherit (self.lib) cluster;

  echo = getExe' pkgs.coreutils "echo";
  grep = getExe' pkgs.gnugrep "grep";
  head = getExe' pkgs.coreutils "head";
  helm = getExe pkgs.kubernetes-helm;
  jq = getExe pkgs.jq;
  kubectl = getExe' pkgs.kubectl "kubectl";
  ping = getExe' pkgs.iputils "ping";
  sed = getExe pkgs.gnused;
  talosctl = getExe pkgs.talosctl;
  test = getExe' pkgs.coreutils "test";
  xargs = getExe' pkgs.findutils "xargs";
  yq = getExe pkgs.yq;

  state = "$DEVENV_STATE/talos";
  writeShellApplication = config @ {name, ...}: "${pkgs.writeShellApplication config}/bin/${name}";
in {
  version = 3;

  tasks = let
    have-talsecret = {
      sh = ''${test} -f $"$TALSECRET"'';
      msg = "Missing talsecret, run `task talos:gensecret` to generate it.";
    };
    have-talosconfig = {
      sh = ''${test} -f $"$TALOSCONFIG"'';
      msg = "Missing talosconfig, run `task talos:genconfig` to generate it.";
    };
    have-kubeconfig = {
      sh = ''${test} -f "$KUBECONFIG"'';
      msg = "Missing kubeconfig, run `task talos:fetch-kubeconfig` to fetch it.";
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
      desc = "Install Helm release ${name}";
      status = [
        ''
          installed_version=$(
            ${helm} list -n ${namespace} -o yaml |
              ${yq} '.[] | select(.name == "${name}") | .app_version' -r
          )
          [ "$installed_version" = "${version}" ]
        ''
      ];
      cmd = writeShellApplication {
        name = "helm-install-${name}";
        runtimeInputs = with pkgs; [coreutils helm];
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
      silent = true;
    };
    waitForNodes = ready: {
      desc = "Wait for nodes${
        if ready
        then " to become ready"
        else ""
      }";
      cmd = writeShellApplication {
        name = "wait-for-nodes";
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
  in {
    bootstrap = {
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
      silent = true;
    };

    gensecret = {
      desc = "Generate Talos secrets";
      status = [
        ''
          ${test} -f "$TALSECRET"
        ''
      ];
      cmds = [
        {
          cmd = writeShellApplication {
            name = "gensecret";
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
      silent = true;
    };

    genconfig = {
      desc = "Generate Talos configs";
      cmd = writeShellApplication {
        name = "genconfig";
        runtimeInputs = with pkgs; [coreutils inputs'.talhelper.packages.default];
        text = ''
          rm -rf "${state}"/*.yaml
          echo "Generating Talos config…"
          talhelper genconfig --config-file="$TALCONFIG" --secret-file="$TALSECRET" --out-dir="${state}"
        '';
      };
      preconditions = [have-talsecret];
      silent = true;
    };

    apply-insecure = {
      desc = "Apply initial cluster config";
      cmd = {
        task = "apply";
        vars.extra_flags = "--insecure";
      };
      silent = true;
    };

    install-k8s = {
      desc = "Bootstrap Kubernetes on Talos nodes";
      cmd = writeShellApplication {
        name = "install-kubernetes";
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
      silent = true;
    };

    fetch-kubeconfig = {
      desc = "Fetch Talos Kubernetes kubeconfig file";
      cmd = writeShellApplication {
        name = "fetch-kubeconfig";
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
      silent = true;
    };

    install-cilium = helmInstall "cilium";
    install-kubelet-csr-approver = helmInstall "kubelet-csr-approver";

    wait-for-nodes = waitForNodes false;
    wait-for-nodes-ready = waitForNodes true;
    wait-for-cilium = {
      desc = "Wait for Cilium to become ready";
      cmd = writeShellApplication {
        name = "cilium-wait";
        runtimeInputs = with pkgs; [cilium-cli coreutils];
        text = ''
          cilium status --wait --wait-duration=30m
        '';
      };

      preconditions = [have-kubeconfig];
      silent = true;
    };
    wait-for-cluster-health = {
      desc = "Wait for Talos cluster to become healthy";
      cmd = writeShellApplication {
        name = "cilium-wait";
        runtimeInputs = [pkgs.talosctl];
        text = ''
          talosctl health --server=false
        '';
      };

      preconditions = [have-talosconfig];
      silent = true;
    };

    apply = {
      desc = "Apply Talos config to all nodes";
      cmd = let
        cmd = writeShellApplication {
          name = "apply";
          runtimeInputs = with pkgs; [bash coreutils inputs'.talhelper.packages.default];
          text = ''
            echo "Applying Talos config to all nodes…"
            talhelper gencommand apply --config-file="$TALCONFIG" --out-dir="${state}" --extra-flags="$1" |
              bash
          '';
        };
      in ''
        "${cmd}" "{{.extra_flags}}"
      '';
      preconditions = [have-talosconfig];
      silent = true;
    };

    diff = {
      desc = "Diff Talos config on all nodes";
      cmd = {
        task = "apply";
        vars.extra_flags = "--dry-run";
      };
      preconditions = [have-talosconfig];
      silent = true;
    };

    ping = {
      desc = "Ping Talos nodes matching the pattern in nodes=";
      cmd = ''
        ${yq} < $TALCONFIG '.nodes[] | select(.hostname | test("^.*{{.nodes}}.*$")) | .ipAddress' \
        | ${xargs} -i ${ping} -c 1 {} {{.CLI_ARGS}}
      '';
      silent = true;
    };

    upgrade-talos = let
      vars = ''
        IP="$(
          ${yq} -r < $TALCONFIG '
            .nodes[] |
            select(.hostname == "{{.node}}") |
            .ipAddress
          '
        )"
        IMAGE="$(
          ${yq} -r < "$DEVENV_STATE/talos/${cluster.name}-{{.node}}.yaml" \
            .machine.install.image |
          ${head} --lines=1
        )"
        VERSION="$(${sed} "s/.*:v//" <<< "$IMAGE")"
      '';
    in {
      desc = "Upgrade Talos on a node";
      requires.vars = ["node"];
      status = [
        ''
          ${vars}
          ${talosctl} version --nodes="$IP" --json |
          ${jq} -r .version.tag |
          ${grep} "v$VERSION"
        ''
      ];
      cmd = ''
        ${vars}
        ${echo} "Upgrading node {{.node}} ($IP) to version $VERSION…"
        ${talosctl} upgrade \
          --nodes="$IP" \
          --image="$IMAGE" \
          --reboot-mode=powercycle \
          --preserve=true
      '';
      preconditions = [have-talosconfig];
      silent = true;
    };

    upgrade-k8s = {
      desc = "Upgrade Kubernetes on a node";
      requires.vars = ["node" "version"];
      status = [
        ''
          ${kubectl} get node -ojson |
          ${jq} -r '.items[] | select(.metadata.name == "{{.node}}").status.nodeInfo.kubeletVersion' |
          ${grep} "v{{.version}}"
        ''
      ];
      cmd = ''
        ${talosctl} upgrade-k8s --nodes={{.node}} --to=v{{.version}}
      '';
      preconditions = [have-talosconfig have-kubeconfig];
      silent = true;
    };

    reset = {
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
          name = "fetch-kubeconfig";
          runtimeInputs = with pkgs; [bash inputs'.talhelper.packages.default];
          text = ''
            talhelper gencommand reset --config-file="$TALCONFIG" --out-dir="${state}" --extra-flags="${flags}" |
              bash
          '';
        };
      preconditions = [have-talosconfig];
      silent = true;
    };
  };
}
