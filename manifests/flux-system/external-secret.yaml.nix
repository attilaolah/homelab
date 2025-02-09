{
  cluster,
  k,
  lib,
  ...
}:
# This requires the external secrets chart to be installed.
# However a dependency is not declared to avoid introducing a cycle.
k.external-secret ./. {
  name = "oci-auth";
  data.".dockerconfigjson" = let
    username = cluster.owner;
    dckr.auth = "$DCKR_AUTH";
    ghcr.auth = "$GHCR_AUTH";
  in
    # Replace JSON-encoded string to avoid escaping the quotes below.
    builtins.replaceStrings [dckr.auth ghcr.auth] [
      ''{{ printf "${username}:%s" .dckr_token | b64enc }}''
      # The GitHub registry ignores the username; only the token matters.
      ''{{ printf "${username}:%s" .ghcr_token | b64enc }}''
    ] (lib.strings.toJSON {
      auths = {
        "docker.io" = {
          inherit username;
          inherit (dckr) auth;
          password = "{{ .dckr_token }}";
        };
        "ghcr.io" = {
          inherit username;
          inherit (ghcr) auth;
          password = "{{ .ghcr_token }}";
        };
      };
    });

  metadata.namespace = baseNameOf ./.;
  spec.target.template.type = "kubernetes.io/dockerconfigjson";
}
