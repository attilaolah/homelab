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
        containers = [
          {
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
              "https://${name}/apks/key.rsa.pub"
              "--connect-to"
              "${name}:443:localhost:8443"
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
            securityContext = {
              allowPrivilegeEscalation = false;
              capabilities.drop = ["ALL"];
              readOnlyRootFilesystem = true;
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
        resources = {
          limits = {
            cpu = "200m";
            memory = "256Mi";
            ephemeral-storage = "64Mi";
          };
          requests = {
            cpu = "50m";
            memory = "64Mi";
            ephemeral-storage = "8Mi";
          };
        };
        securityContext = {
          runAsNonRoot = true;
          runAsUser = 101;
          seccompProfile.type = "RuntimeDefault";
        };
        automountServiceAccountToken = false;
      };
    };
  };
})
