# https://artifacthub.io/packages/helm/bitnami/keycloak#parameters
{k, ...}: {
  # Use our own database.
  postgresql.enabled = false;
  # CloudNative PG managed cluster.
  externalDatabase = {
    existingSecret = "${k.fluxcd.ksname ../database}-app";
    existingSecretHostKey = "host";
    existingSecretPortKey = "port";
    existingSecretUserKey = "user";
    existingSecretDatabaseKey = "dbname";
    existingSecretPasswordKey = "password";
  };
  extraEnvVars = [
    {
      name = "JAVA_OPTS";
      # IPv6 should be fine, but just in case.
      value = "-Djava.net.preferIPv4Stack=true";
    }
  ];
}
