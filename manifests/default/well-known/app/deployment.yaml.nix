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
            image = "nginx:${v.nginx.docker}";
            ports = [{containerPort = 8443;}];
            volumeMounts = [
              k.pki.mount
              {
                name = "config";
                mountPath = "/etc/nginx/conf.d/default.conf";
                subPath = "config";
                readOnly = true;
              }
              {
                name = "config";
                mountPath = "/docker-entrypoint.d/10-patch-config.sh";
                subPath = "entrypoint";
                readOnly = true;
              }
              {
                name = "var-cache";
                mountPath = "/var/cache/nginx";
              }
              {
                name = "var-run";
                mountPath = "/var/run";
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
            name = "config";
            configMap = {inherit name;};
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
            cpu = "100m";
            memory = "128Mi";
            ephemeral-storage = "16Mi";
          };
          requests = {
            cpu = "50m";
            memory = "64Mi";
            ephemeral-storage = "8Mi";
          };
        };
        securityContext = {
          runAsUser = 1000;
          runAsNonRoot = true;
          seccompProfile.type = "RuntimeDefault";
        };
        automountServiceAccountToken = false;
      };
    };
  };
})
