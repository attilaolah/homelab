let
  vp = v: "v${v}"; # v prefix
in {
  # Format:
  # dep.datasource = [repository version transform]
  # If transform is not provided, the default is used: (v: v).
  cert-manager.helm = ["https://charts.jetstack.io" "1.17.1"];
  cilium.helm = ["https://helm.cilium.io" "1.17.2"];
  cloudnative-pg.helm = ["https://cloudnative-pg.io/charts" "0.23.2"];
  descheduler.helm = ["https://kubernetes-sigs.github.io/descheduler" "0.32.2"];
  external-secrets.helm = ["https://charts.external-secrets.io" "0.15.0"];
  flux-operator.helm = ["oci://ghcr.io/controlplaneio-fluxcd/charts" "0.18.0"];
  flux.github-releases = ["fluxcd/flux2" "2.5.1"];
  goldilocks.helm = ["https://charts.fairwinds.com/stable" "9.0.1"];
  homepage.docker = ["ghcr.io/gethomepage/homepage" "1.0.4" vp];
  homepage.helm = ["https://jameswynn.github.io/helm-charts" "2.0.2"];
  inadyn.docker = ["troglobit/inadyn" "2.12.0" vp];
  inadyn.helm = ["https://charts.philippwaller.com" "1.1.0"];
  ingress-nginx.helm = ["https://kubernetes.github.io/ingress-nginx" "4.12.1"];
  jaeger.helm = ["https://jaegertracing.github.io/helm-charts" "3.4.1"];
  k0s.docker = ["attilaolah/k0s" "1.32.2.0"];
  k0s.github-releases = ["k0sproject/k0s" "1.32.2+k0s.0" vp];
  keycloak.helm = ["oci://registry-1.docker.io/bitnamicharts" "24.4.13"];
  kube-prometheus-stack.helm = ["https://prometheus-community.github.io/helm-charts" "70.3.0"];
  kubelet-csr-approver.helm = ["https://postfinance.github.io/kubelet-csr-approver" "1.2.6"];
  kubernetes.github-releases = ["kubernetes/kubernetes" "1.32.3" vp];
  local-path-provisioner.github-releases = ["rancher/local-path-provisioner" "0.0.31" vp];
  loki.helm = ["https://grafana.github.io/helm-charts" "6.28.0"];
  metrics-server.helm = ["https://kubernetes-sigs.github.io/metrics-server" "3.12.2"];
  minecraft-bedrock.helm = ["https://itzg.github.io/minecraft-server-charts" "2.8.4"];
  node-feature-discovery.helm = ["https://kubernetes-sigs.github.io/node-feature-discovery/charts" "0.17.2"];
  pause.docker = ["https://registry.k8s.io/pause" "3.9"];
  reloader.helm = ["oci://ghcr.io/stakater/charts" "2.0.0"];
  spegel.helm = ["oci://ghcr.io/spegel-org/helm-charts" "0.1.0"];
  talos.github-releases = ["siderolabs/talos" "1.9.5" vp];
  vector.helm = ["https://helm.vector.dev" "0.41.0"];
  vpa.helm = ["https://charts.fairwinds.com/stable" "4.7.2"];
  zfs-localpv.helm = ["https://openebs.github.io/zfs-localpv" "2.7.1"];

  # Kubernetes API versions
  Certificate.cert-manager.io = "v1";
  CiliumL2AnnouncementPolicy.cilium.io = "v2alpha1";
  CiliumLoadBalancerIPPool.cilium.io = "v2alpha1";
  Cluster.postgresql.cnpg.io = "v1";
  ClusterIssuer.cert-manager.io = "v1";
  ClusterSecretStore.external-secrets.io = "v1beta1";
  ConfigMap = "v1";
  Deployment.apps = "v1";
  ExternalSecret.external-secrets.io = "v1beta1";
  FluxInstance.fluxcd.controlplane.io = "v1";
  GitRepository.source.toolkit.fluxcd.io = "v1";
  HelmRelease.helm.toolkit.fluxcd.io = "v2";
  HelmRepository.source.toolkit.fluxcd.io = "v1";
  Ingress.networking.k8s.io = "v1";
  KubeletConfiguration.kubelet.config.k8s.io = "v1beta1";
  Kustomization.kustomize.config.k8s.io = "v1beta1";
  Kustomization.kustomize.toolkit.fluxcd.io = "v1";
  Namespace = "v1";
  Role.rbac.authorization.k8s.io = "v1";
  RoleBinding.rbac.authorization.k8s.io = "v1";
  Service = "v1";
  StorageClass.storage.k8s.io = "v1";
}
