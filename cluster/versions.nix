let
  vp = v: "v${v}"; # v prefix
in {
  # Format:
  # dep.datasource = [repository version transform]
  # If transform is not provided, the default is used: (v: v).
  cert-manager.helm = ["https://charts.jetstack.io" "1.17.0"];
  cilium.helm = ["https://helm.cilium.io" "1.17.0"];
  descheduler.helm = ["https://kubernetes-sigs.github.io/descheduler" "0.32.1"];
  external-secrets.helm = ["https://charts.external-secrets.io" "0.14.0"];
  flux-operator.helm = ["oci://ghcr.io/controlplaneio-fluxcd/charts" "0.13.0"];
  flux.github-releases = ["fluxcd/flux2" "2.4.0"];
  goldilocks.helm = ["https://charts.fairwinds.com/stable" "9.0.1"];
  grafana.helm = ["https://grafana.github.io/helm-charts" "8.9.0"];
  homepage.docker = ["ghcr.io/gethomepage/homepage" "0.10.9" vp];
  homepage.helm = ["https://jameswynn.github.io/helm-charts" "2.0.1"];
  inadyn.docker = ["troglobit/inadyn" "2.12.0" vp];
  inadyn.helm = ["https://charts.philippwaller.com" "1.1.0"];
  ingress-nginx.helm = ["https://kubernetes.github.io/ingress-nginx" "4.12.0"];
  kube-prometheus-stack.helm = ["https://prometheus-community.github.io/helm-charts" "69.2.0"];
  kubelet-csr-approver.helm = ["https://postfinance.github.io/kubelet-csr-approver" "1.2.5"];
  kubernetes.github-releases = ["kubernetes/kubernetes" "1.32.1" vp];
  local-path-provisioner.github-releases = ["rancher/local-path-provisioner" "0.0.31" vp];
  loki.helm = ["https://grafana.github.io/helm-charts" "6.25.1"];
  metrics-server.helm = ["https://kubernetes-sigs.github.io/metrics-server" "3.12.2"];
  minecraft-bedrock.helm = ["https://itzg.github.io/minecraft-server-charts" "2.8.2"];
  node-feature-discovery.helm = ["https://kubernetes-sigs.github.io/node-feature-discovery/charts" "0.17.1"];
  rancher.helm = ["https://releases.rancher.com/server-charts/latest" "2.10.2"];
  reloader.helm = ["oci://ghcr.io/stakater/charts" "1.2.1"];
  spegel.helm = ["oci://ghcr.io/spegel-org/helm-charts" "0.0.30" vp];
  talos.github-releases = ["siderolabs/talos" "1.9.3" vp];
  vector.helm = ["https://helm.vector.dev" "0.40.0"];
  vpa.helm = ["https://charts.fairwinds.com/stable" "4.7.1"];
  zfs-localpv.helm = ["https://openebs.github.io/zfs-localpv" "2.6.2"];
}
