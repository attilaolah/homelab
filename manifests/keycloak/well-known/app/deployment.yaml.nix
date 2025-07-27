{
  cluster,
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
        inherit (k.pod) automountServiceAccountToken securityContext;

        containers = [
          {
            inherit (k.container) securityContext;

            name = "nginx";
            image = "nginx:${v.nginx.docker}";
            ports = [{containerPort = 8443;}];
            livenessProbe.exec.command = with k.pki; [
              "curl"
              "https://localhost:8443/.well-known/webfinger?resource=acct:kubelet@${cluster.domain}"
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
            resources = let
              requests = {
                cpu = "50m";
                memory = "128Mi";
                ephemeral-storage = "128Mi";
              };
            in {
              limits = requests // {cpu = "1";};
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
      };
    };
  };
})
