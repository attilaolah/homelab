let
  vp = v: "v${v}"; # v prefix
in {
  # Format:
  # dep.datasource = [repository version transform]
  # If transform is not provided, the default is used: (v: v).
  cert-manager.helm = ["https://charts.jetstack.io" "1.16.2"];
  cilium.helm = ["https://helm.cilium.io" "1.16.4"];
  descheduler.helm = ["https://kubernetes-sigs.github.io/descheduler" "0.31.0"];
  external-secrets.helm = ["https://charts.external-secrets.io" "0.11.0"];
  flux-operator.helm = ["oci://ghcr.io/controlplaneio-fluxcd/charts" "0.10.0"];
  flux.github-releases = ["https://github.com/fluxcd/flux2" "2.4.0"];
  goldilocks.helm = ["https://charts.fairwinds.com/stable" "9.0.1"];
  grafana.helm = ["https://grafana.github.io/helm-charts" "8.6.4"];
  homepage.github-releases = ["https://github.com/gethomepage/homepage" "0.9.13" vp];
  homepage.helm = ["https://jameswynn.github.io/helm-charts" "2.0.1"];
  inadyn.github-releases = ["https://github.com/troglobit/inadyn" "2.12.0" vp];
  inadyn.helm = ["https://charts.philippwaller.com" "1.1.0"];
  ingress-nginx.helm = ["https://kubernetes.github.io/ingress-nginx" "4.11.3"];
  kubelet-csr-approver.helm = ["https://postfinance.github.io/kubelet-csr-approver" "1.2.3"];
  kubernetes.github-releases = ["https://github.com/kubernetes/kubernetes" "1.31.2" vp];
  local-path-provisioner.github-releases = ["https://github.com/rancher/local-path-provisioner" "0.0.30" vp];
  loki.helm = ["https://grafana.github.io/helm-charts" "6.23.0"];
  metrics-server.helm = ["https://kubernetes-sigs.github.io/metrics-server" "3.12.2"];
  minecraft-bedrock.helm = ["https://itzg.github.io/minecraft-server-charts" "2.8.2"];
  node-feature-discovery.helm = ["https://kubernetes-sigs.github.io/node-feature-discovery/charts" "0.16.6"];
  rancher.helm = ["https://releases.rancher.com/server-charts/latest" "2.10.1"];
  reloader.helm = ["oci://ghcr.io/stakater/charts" "1.2.0"];
  spegel.helm = ["oci://ghcr.io/spegel-org/helm-charts" "0.0.27" vp];
  talos.github-releases = ["https://github.com/siderolabs/talos" "1.8.2" vp];
  vector.helm = ["https://helm.vector.dev" "0.38.0"];
  vpa.helm = ["https://charts.fairwinds.com/stable" "4.7.1"];
  zfs-localpv.helm = ["https://openebs.github.io/zfs-localpv" "2.6.2"];
}
