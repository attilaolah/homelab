{withSystem, ...}: {...}: {
  perSystem = ctx @ {
    system,
    pkgs,
    ...
  }: {
    packages.taskfile-talos = withSystem system (
      {
        inputs',
        config,
        ...
      }: let
        inherit (pkgs.lib) getExe getExe';

        bash = getExe pkgs.bash;
        cilium = getExe pkgs.cilium-cli;
        flux = getExe pkgs.fluxcd;
        grep = getExe' pkgs.gnugrep "grep";
        helmfile = getExe pkgs.helmfile;
        jq = getExe pkgs.jq;
        kubectl = getExe' pkgs.kubectl "kubectl";
        ping = getExe' pkgs.iputils "ping";
        rm = getExe' pkgs.coreutils "rm";
        sleep = getExe' pkgs.coreutils "sleep";
        # talhelper = getExe' todo_talhelper "talhelper";
        talhelper = getExe' inputs'.talhelper.packages.default "talhelper";
        talosctl = getExe pkgs.talosctl;
        test = getExe' pkgs.coreutils "test";
        xargs = getExe' pkgs.findutils "xargs";
        yq = getExe pkgs.yq;

        state = "$DEVENV_STATE/talos";
        writeYAML = (pkgs.formats.yaml {}).generate;
      in
        writeYAML "taskfile.yaml" {
          version = 3;

          tasks = let
            node-exists = {
              sh = "${talosctl} get machineconfig --nodes={{.node}}";
              msg = "Talos node not found.";
            };
            kubeconfig-exists = {
              sh = "${test} -f $KUBECONFIG";
              msg = "Missing kubeconfig, run `task talos:fetch-kubeconfig` to fetch it.";
            };
          in {
            bootstrap = {
              desc = "Bootstrap Talos cluster";
              cmds = let
                # Wait for nodes to report not ready.
                # CNI is disabled initially, hence the nodes are not expected to be in ready state.
                waitForNodes = ready: ''
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
                # TODO: gensecret
                {task = "genconfig";}
                {task = "apply-insecure";}
                {task = "install-k8s";}
                {task = "fetch-kubeconfig";}
                (waitForNodes false)
                {task = "install-cilium";}
                (waitForNodes true)
                "${talosctl} health --server=false"
                {task = "install-flux";}
              ];
            };

            genconfig = {
              desc = "Bootstrap Talos: #1 - generate configs";
              cmd = ''
                ${rm} -rf ${state}
                ${talhelper} genconfig --config-file="$TALCONFIG" --secret-file="$TALSECRET" --out-dir="${state}"
              '';
            };

            apply-insecure = {
              desc = "Bootstrap Talos: #2 - apply initial config";
              cmd = {
                task = "apply";
                vars.extra_flags = "--insecure";
              };
            };

            install-k8s = {
              desc = "Bootstrap Talos: #3 - bootstrap k8s cluster";
              cmd = ''
                echo "Installing Talos, this might take a while and print errors"
                until ${talhelper} gencommand bootstrap --config-file="$TALCONFIG" --out-dir=${state} |
                  ${bash}
                  do ${sleep} 2
                done
              '';
            };

            fetch-kubeconfig = {
              desc = "Fetch Talos Kubernetes kubeconfig file";
              cmd = ''
                until ${talhelper} gencommand kubeconfig --config-file="$TALCONFIG" --out-dir=${state} \
                  --extra-flags="--merge=false --force $KUBECONFIG" |
                  ${bash}
                  do ${sleep} 2
                done
              '';
            };

            install-cilium = {
              desc = "Bootstrap Talos: #4 - install cilium";
              cmds = let
                helmfile-yaml = import ../talos/apps/helmfile.nix ctx;
              in [
                "${helmfile} apply --file=${helmfile-yaml} --skip-diff-on-install --suppress-diff"
                "${cilium} status --wait"
              ];
              preconditions = [kubeconfig-exists];
            };

            install-flux = {
              # TODO: Try to get the Flux token from Bitwarden.
              desc = "Bootstrap Talos: #5 - install flux";
              cmd = let
                cluster = import ../cluster ctx;
              in ''
                ${flux} bootstrap github \
                  --owner=${cluster.github.owner} \
                  --repository=${cluster.github.repository} \
                  --branch=flux \
                  --path=./flux \
                  --cluster-domain=${cluster.domain} \
                  --personal
              '';
              preconditions = [kubeconfig-exists];
            };

            apply = {
              desc = "Apply Talos config to all nodes";
              cmd = ''
                ${talhelper} gencommand apply \
                  --config-file="$TALCONFIG" --out-dir=${state} --extra-flags="{{.extra_flags}}" |
                  ${bash}
              '';
            };

            diff = {
              desc = "Diff Talos config on all nodes";
              cmd = {
                task = "apply";
                vars.extra_flags = "--dry-run";
              };
            };

            dashboard = {
              desc = "Show Talos dashboard on the first node";
              cmd = ''
                node="$(${yq} < $TALOSCONFIG '.context as $c | .contexts[$c] | .nodes[0]' -r)"
                ${talosctl} dashboard --nodes="$node"
              '';
            };

            ping = {
              desc = "Ping Talos nodes matching the pattern in nodes=";
              cmd = ''
                ${yq} < $TALCONFIG '.nodes[] | select(.hostname | test("^.*{{.nodes}}.*$")) | .ipAddress' \
                | ${xargs} -i ${ping} -c 1 {} {{.CLI_ARGS}}
              '';
            };

            upgrade-talos = {
              desc = "Upgrade Talos on a node";
              requires.vars = ["node" "version"];
              preconditions = [node-exists];
              status = [
                ''
                  ${talosctl} version --nodes={{.node}} --json |
                  ${jq} -r .version.tag |
                  ${grep} 'v{{.version}}
                ''
              ];
              cmd = ''
                ${talosctl} upgrade \
                  --nodes={{.node}} \
                  --image=ghcr.io/siderolabs/installer:v{{.version}} \
                  --reboot-mode=powercycle \
                  --preserve=true
              '';
            };

            upgrade-k8s = {
              desc = "Upgrade Kubernetes on a node";
              requires.vars = ["node" "version"];
              preconditions = [node-exists];
              status = [
                ''
                  ${kubectl} get node -ojson |
                  ${jq} -r '.items[] | select(.metadata.name == "{{.node}}").status.nodeInfo.kubeletVersion' |
                  ${grep} 'v{{.version}}
                ''
              ];
              cmd = ''
                ${talosctl} kpgrade-k8s --nodes={{.node}} --to=v{{.version}}
              '';
            };

            reset = {
              desc = "Resets Talos nodes back to maintenance mode";
              prompt = "Are you sure? This will destroy your cluster and reset the nodes back to maintenance mode.";
              cmd = ''
                ${talhelper} gencommand reset \
                  --config-file=$TALCONFIG \
                  --out-dir="${state}" \
                  --extra-flags="--reboot --system-labels-to-wipe=STATE --system-labels-to-wipe=EPHEMERAL --graceful=false --wait=false" |
                  ${bash}
              '';
            };
          };
        }
    );
  };
}
