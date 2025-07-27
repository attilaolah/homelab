args @ {
  k,
  lib,
  v,
  ...
}:
k.api "Deployment.apps" (let
  inherit (values) labels config;
  inherit (lib.strings) concatStringsSep;

  values = import ./values.nix args;

  app = k.nsname ./.;
  name = k.fluxcd.ksname ./.;

  tlsVol = "tls";
  configVol = "config";
  configPath = "/etc/${config}";

  pwVar = "REDIS_PASSWORD";
  pwRef = "\${${pwVar}}";

  shell = parts: ["sh" "-c" (concatStringsSep " " parts)];
  probe.exec.command = shell [
    "redis-cli"
    "--tls"
    "--cacert"
    k.pki.ca
    # NOTE: --cert and --key are technically not necessary since tls-auth-clients is disabled.
    # Here it is passed anyway in case we get to re-enable tls-auth-clients when oauth2-proxy supports it.
    "--cert"
    k.pki.crt
    "--key"
    k.pki.key
    "--pass"
    pwRef
    "--no-auth-warning"
    "ping"
  ];
in {
  metadata = {inherit name labels;};
  spec = {
    replicas = 1;
    selector.matchLabels = values.selector;
    template = {
      metadata = {inherit labels;};
      spec = {
        inherit (k.pod) automountServiceAccountToken securityContext;
        containers = [
          {
            inherit (k.defaults) imagePullPolicy;
            inherit (k.container) securityContext;
            name = app;
            image = "${app}:${v."${app}".docker}";
            args = shell ["redis-server" configPath "--requirepass" pwRef];
            env = [
              {
                name = "TZ";
                value = "UTC";
              }
              {
                name = pwVar;
                valueFrom.secretKeyRef = {
                  inherit name;
                  key = "password";
                };
              }
            ];
            ports = [
              {
                inherit (k.defaults) protocol;
                name = values.protocol;
                containerPort = values.port;
              }
            ];
            livenessProbe = probe;
            readinessProbe = probe;
            resources = let
              guaranteed = {
                cpu = "100m";
                memory = "128Mi";
                ephemeral-storage = "512Mi";
              };
            in {
              limits = guaranteed;
              requests = guaranteed;
            };
            volumeMounts = [
              {
                name = configVol;
                mountPath = configPath;
                subPath = config;
              }
              k.pki.mount
            ];
          }
        ];
        volumes = [
          {
            name = configVol;
            configMap.name = name;
          }
          {
            name = tlsVol;
            secret.secretName = "${name}-tls";
          }
        ];
      };
    };
  };
})
