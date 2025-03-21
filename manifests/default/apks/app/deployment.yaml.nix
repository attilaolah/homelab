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
            image = "attilaolah/k0s:${v.k0s.docker}";
            imagePullPolicy = "Always";
            ports = [
              {
                name = "https";
                containerPort = 8443;
              }
            ];
            livenessProbe.exec.command = [
              "curl"
              "https://${name}/apks/key.rsa.pub"
              "--connect-to"
              "${name}:443:localhost:8443"
              "--cert"
              "/etc/tls/tls.crt"
              "--key"
              "/etc/tls/tls.key"
              "--cacert"
              "/etc/tls/ca.crt"
            ];
            volumeMounts = [
              {
                name = "tls";
                mountPath = "/etc/tls";
                readOnly = true;
              }
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
