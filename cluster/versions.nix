let
  vp = v: "v${v}"; # v prefix
in {
  # Format:
  # dep.datasource = [repository version transform]
  # If transform is not provided, the default is used: (v: v).
  busybox.docker = ["busybox" "1.37.0"];
  cert-manager.helm = ["https://charts.jetstack.io" "1.18.2"];
  cilium.helm = ["https://helm.cilium.io" "1.17.6"];
  cloudnative-pg.helm = ["https://cloudnative-pg.io/charts" "0.25.0"];
  descheduler.helm = ["https://kubernetes-sigs.github.io/descheduler" "0.33.0"];
  external-secrets.helm = ["https://charts.external-secrets.io" "0.18.2"];
  flux-operator.helm = ["oci://ghcr.io/controlplaneio-fluxcd/charts" "0.25.0"];
  flux.github-releases = ["fluxcd/flux2" "2.6.4"];
  goldilocks.docker = ["us-docker.pkg.dev/fairwinds-ops/oss/goldilocks" "4.14.0" vp];
  goldilocks.helm = ["https://charts.fairwinds.com/stable" "9.0.2"];
  homepage.docker = ["ghcr.io/gethomepage/homepage" "1.4.0" vp];
  homepage.helm = ["https://jameswynn.github.io/helm-charts" "2.1.0"];
  inadyn.docker = ["troglobit/inadyn" "2.12.0" vp];
  inadyn.helm = ["https://charts.philippwaller.com" "1.1.0"];
  ingress-nginx.helm = ["https://kubernetes.github.io/ingress-nginx" "4.13.0"];
  jaeger-collector.docker = ["jaegertracing/jaeger-collector" "1.71.0"];
  jaeger-query.docker = ["jaegertracing/jaeger-query" "1.71.0"];
  jaeger.helm = ["https://jaegertracing.github.io/helm-charts" "3.4.1"];
  k0s.docker = ["attilaolah/k0s" "1.33.3.0"];
  k0s.github-releases = ["k0sproject/k0s" "1.33.3+k0s.0" vp];
  keycloak.helm = ["oci://registry-1.docker.io/bitnamicharts" "24.8.1"];
  kube-prometheus-stack.helm = ["https://prometheus-community.github.io/helm-charts" "75.15.0"];
  kubelet-csr-approver.helm = ["https://postfinance.github.io/kubelet-csr-approver" "1.2.10"];
  kubernetes.github-releases = ["kubernetes/kubernetes" "1.33.3" vp];
  local-path-provisioner.github-releases = ["rancher/local-path-provisioner" "0.0.31" vp];
  loki.helm = ["https://grafana.github.io/helm-charts" "6.33.0"];
  metrics-server.helm = ["https://kubernetes-sigs.github.io/metrics-server" "3.13.0"];
  minecraft-bedrock.helm = ["oci://ghcr.io/itzg/minecraft-server-charts" "2.8.4"];
  nginx.docker = ["nginx" "1.29.0"];
  node-feature-discovery.helm = ["https://kubernetes-sigs.github.io/node-feature-discovery/charts" "0.17.3"];
  oauth2-proxy.docker = ["quay.io/oauth2-proxy/oauth2-proxy" "7.10.0" vp];
  pause.docker = ["registry.k8s.io/pause" "3.9"];
  reloader.helm = ["oci://ghcr.io/stakater/charts" "2.1.5"];
  spegel.helm = ["oci://ghcr.io/spegel-org/helm-charts" "0.3.0"];
  talos.github-releases = ["siderolabs/talos" "1.10.5" vp];
  vector.helm = ["https://helm.vector.dev" "0.44.0"];
  vpa.helm = ["https://charts.fairwinds.com/stable" "4.8.0"];
  zfs-localpv.helm = ["https://openebs.github.io/zfs-localpv" "2.8.0"];

  # Kubernetes API versions
  Certificate.cert-manager.io = "v1";
  CiliumL2AnnouncementPolicy.cilium.io = "v2alpha1";
  CiliumLoadBalancerIPPool.cilium.io = "v2alpha1";
  Cluster.postgresql.cnpg.io = "v1";
  ClusterIssuer.cert-manager.io = "v1";
  ClusterSecretStore.external-secrets.io = "v1";
  ConfigMap = "v1";
  Deployment.apps = "v1";
  ExternalSecret.external-secrets.io = "v1";
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
