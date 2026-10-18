{
  gawk,
  iproute2,
  writeShellApplication,
}:
writeShellApplication {
  name = "caddy-vrrp-config-gen";
  runtimeInputs = [gawk iproute2];
  text = builtins.readFile ./vrrp_config_gen.sh;
}
