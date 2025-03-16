{
  pkgs,
  self,
  inputs',
  ...
}: let
  inherit (pkgs) lib;
  inherit (lib) getExe getExe';
  inherit (self.lib) cluster;

  bash = getExe pkgs.bash;
  cilium = getExe pkgs.cilium-cli;
  echo = getExe' pkgs.coreutils "echo";
  grep = getExe' pkgs.gnugrep "grep";
  head = getExe' pkgs.coreutils "head";
  helm = getExe pkgs.kubernetes-helm;
  jq = getExe pkgs.jq;
  kubectl = getExe' pkgs.kubectl "kubectl";
  ping = getExe' pkgs.iputils "ping";
  rm = getExe' pkgs.coreutils "rm";
  sed = getExe pkgs.gnused;
  sleep = getExe' pkgs.coreutils "sleep";
  talhelper = getExe' inputs'.talhelper.packages.default "talhelper";
  talosctl = getExe pkgs.talosctl;
  test = getExe' pkgs.coreutils "test";
  xargs = getExe' pkgs.findutils "xargs";
  yq = getExe pkgs.yq;

  state = "$DEVENV_STATE/talos";
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
  in {
    bootstrap = {
      desc = "Bootstrap Talos cluster";
      cmds = let
        # Wait for nodes to report not ready.
        # CNI is disabled initially, hence the nodes are not expected to be in ready state.
        waitForNodes = ready: ''
          ${echo} "Waiting for nodes…"
          if [ "{{.wait}}" = "true" ]; then
            until ${kubectl} wait --for=condition=Ready=${
            if ready
            then "true"
            else "false"
          } nodes --all --timeout=120s
              do ${sleep} 2
            done
          fi
        '';
      in [
        {task = "gensecret";}
        {task = "genconfig";}
        {task = "ping";}
        {task = "apply-insecure";}
        {task = "install-k8s";}
        {task = "fetch-kubeconfig";}
        (waitForNodes false)
        {task = "install-cilium";}
        (waitForNodes true)
        "${talosctl} health --server=false"
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
        ''${talhelper} gensecret > "$TALSECRET"''
        {
          task = ":sops:encrypt-file";
          vars.file = "$TALSECRET";
        }
      ];
      silent = true;
    };

    genconfig = {
      desc = "Generate Talos configs";
      cmd = ''
        ${rm} -rf ${state}/*.yaml
        ${echo} "Generating Talos config…"
        ${talhelper} genconfig --config-file="$TALCONFIG" --secret-file="$TALSECRET" --out-dir="${state}"
      '';
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
      cmd = ''
        ${echo} "Installing Kubernetes, this might take a while…"
        until ${talhelper} gencommand bootstrap --config-file="$TALCONFIG" --out-dir=${state} |
          ${bash}
          do ${sleep} 20
          ${echo} Retrying…
        done
      '';
      preconditions = [have-talosconfig];
      silent = true;
    };

    fetch-kubeconfig = {
      desc = "Fetch Talos Kubernetes kubeconfig file";
      cmd = ''
        ${echo} "Fetching kubeconfig…"
        until ${talhelper} gencommand kubeconfig --config-file="$TALCONFIG" --out-dir=${state} \
          --extra-flags="--merge=false --force $KUBECONFIG" |
          ${bash}
          do ${sleep} 2
          ${echo} Retrying…
        done
      '';
      preconditions = [have-talosconfig];
      silent = true;
    };

    install-cilium = let
      inherit (release.metadata) name;
      inherit (release.spec.chart.spec) chart;
      inherit (release.spec.chart.spec) version;

      namespace = "kube-system";
      release = import ../../../manifests/kube-system/cilium/app/helm-release.yaml.nix {
        k = self.lib.kubernetes;
        v = cluster.versions;
      };
      repo-url = builtins.elemAt cluster.versions-data.cilium.helm 0;
    in {
      desc = "Install Cilium";
      status = [
        ''
          installed_version=$(
            ${helm} list -n kube-system -o yaml |
              ${yq} '.[] | select(.name == "cilium") | .app_version' -r
          )
          [ "$installed_version" = "${version}" ]
        ''
      ];
      cmd = ''
        set -euo pipefail

        ${echo} "Installing Cilium version ${version}, stand by…"
        ${helm} repo add ${chart} "${repo-url}"
        ${helm} repo update ${chart}
        ${helm} install ${name} ${chart}/${name} --namespace=${namespace} --version=${version} --values="$MANIFESTS/kube-system/cilium/app/values.yaml"

        ${echo} "Done, waiting for Cilium to become ready…"
        ${cilium} status --wait --wait-duration=30m
      '';
      preconditions = [have-kubeconfig];
      silent = true;
    };

    apply = {
      desc = "Apply Talos config to all nodes";
      cmd = ''
        ${echo} "Applying Talos config to all nodes…"
        ${talhelper} gencommand apply \
          --config-file="$TALCONFIG" --out-dir=${state} --extra-flags="{{.extra_flags}}" |
          ${bash}
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
      in ''
        ${talhelper} gencommand reset \
          --config-file=$TALCONFIG \
          --out-dir="${state}" \
          --extra-flags="${flags}" |
          ${bash}
      '';
      preconditions = [have-talosconfig];
      silent = true;
    };
  };
}
