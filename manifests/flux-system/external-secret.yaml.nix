{
  k,
  lib,
  ...
}:
k.external-secret ./. {
  name = "oci-auth";
  data.".dockerconfigjson" = let
    username = "flux";
    dckr.auth = "$DCKR_AUTH";
    ghcr.auth = "$GHCR_AUTH";
  in
    # Replace JSON-encoded string to avoid escaping the quotes below.
    builtins.replaceStrings [dckr.auth ghcr.auth] [
      ''{{ printf "${username}:%s" .dckr_token | b64enc }}''
      ''{{ printf "${username}:%s" .ghcr_token | b64enc }}''
    ] (lib.strings.toJSON {
      auths = {
        "registry-1.docker.io" = {
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
