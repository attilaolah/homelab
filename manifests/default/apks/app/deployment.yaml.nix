{
  k,
  v,
  ...
}:
k.api "Deployment.apps" (let
  name = k.appname ./.;
  labels = import ./labels.nix;
in {
  metadata = {inherit name labels;};
  spec = {
    replicas = 1;
    selector.matchLabels = labels;
    template = {
      metadata = {inherit labels;};
      spec = {
        inherit (k.pod) automountServiceAccountToken;
        containers = [
          {
            inherit (k.container) securityContext;

            name = "nginx";
            # TODO: remove pin after cleaning up local cache
            image = "attilaolah/k0s:${v.k0s.docker}@sha256:07a29754e55e6e5da59254aee53da597d2cbc4952cbc566600e379235e9028d6";
            imagePullPolicy = "Always";
            ports = [
              {
                name = "https";
                containerPort = 8443;
              }
            ];
            livenessProbe.exec.command = with k.pki; [
              "curl"
              "https://localhost:8443/apks/key.rsa.pub"
              "--cert"
              crt
              "--key"
              key
              "--cacert"
              ca
            ];
            volumeMounts = [
              k.pki.mount
              {
                name = "var-cache";
                mountPath = "/var/cache/nginx";
              }
              {
                name = "var-run";
                mountPath = "/var/run/nginx";
              }
            ];
            resources = rec {
              # Higher CPU limit for liveness probe.
              limits = requests // {cpu = "200m";};
              requests = {
                cpu = "50m";
                memory = "256Mi";
                ephemeral-storage = "256Mi";
              };
            };
          }
        ];
        volumes = [
          {
            name = "tls";
            secret.secretName = "${name}-tls";
          }
          {
            name = "var-cache";
            emptyDir = {};
          }
          {
            name = "var-run";
            emptyDir = {};
          }
        ];
        securityContext = k.pod.securityContext // {runAsUser = 101;};
      };
    };
  };
})
