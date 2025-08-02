{
  k,
  self,
  ...
}:
k.fluxcd.helm-release ./. {
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
