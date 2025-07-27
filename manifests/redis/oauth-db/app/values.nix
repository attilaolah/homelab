{
  k,
  v,
  ...
}: let
  ns = k.nsname ./.;
  instance = "${ns}-${k.appname ./.}";
  group = "app.kubernetes.io";
  selector = k.annotations.group group {
    inherit instance;
    name = ns;
  };
in {
  inherit selector;
  port = 6379;
  protocol = "rediss";
  labels =
    selector
    // (k.annotations.group group {
      component = "database";
      version = v.${ns}.docker;
    });
  config = "${ns}.conf";
}
