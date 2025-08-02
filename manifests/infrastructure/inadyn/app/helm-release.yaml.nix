{
  k,
  self,
  ...
}:
k.fluxcd.helm-release ./. {
  # TODO: remove when upstream merges:
  # https://github.com/philippwaller/helm-charts/pull/64
  spec.postRenderers = [
    {
      kustomize.patches = [
        {
          target = {
            kind = "Deployment";
            name = k.appname ./.;
          };
          patch = self.lib.yaml.format [
            {
              op = "add";
              path = "/spec/template/spec/automountServiceAccountToken";
              value = false;
            }
            {
              op = "remove";
              path = "/spec/template/spec/serviceAccountName";
            }
          ];
        }
      ];
    }
  ];
}
