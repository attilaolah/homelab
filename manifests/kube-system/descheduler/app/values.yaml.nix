# https://github.com/kubernetes-sigs/descheduler/blob/master/charts/descheduler/values.yaml
{
  k,
  v,
  ...
}: {
  image.tag = v.descheduler.docker;

  securityContext = {inherit (k.container.securityContext) runAsUser;};
  podSecurityContext = k.pod.securityContext;
}
