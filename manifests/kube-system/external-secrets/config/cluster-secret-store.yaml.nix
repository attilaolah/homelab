{k, ...}:
k.api "ClusterSecretStore.external-secrets.io" {
  metadata.name = "gcp-secrets";
  spec.provider.gcpsm = {
    projectID = "dornhaus";
    auth.secretRef.secretAccessKeySecretRef = {
      name = "gcp-secrets-service-account";
      namespace = "kube-system";
      key = "key";
    };
  };
}
