{...}: {self, ...}: {
  perSystem = {pkgs, ...}: let
    inherit (builtins) attrValues filter mapAttrs readDir;
    inherit (pkgs.lib) lists sources strings;
    inherit (self.lib) cluster;

    # Process all files in //manifests that end in .yaml.nix.
    root = sources.sourceFilesBySuffices ../../manifests [".nix"];

    # Load sources by file extension.
    srcs = filter (item: item != null) (lists.flatten (walk root root));
    walk = root: dir: (attrValues (mapAttrs (
      name: type:
        if type == "directory"
        then walk root "${dir}/${name}" # recursive call
        else if strings.hasSuffix ".yaml.nix" name
        then toYAML root dir name # yaml conversion
        else null # ignore
    ) (readDir dir)));

    # Generate YAML contents.
    toYAML = root: dir: name: let
      # File name.
      absPath = "${dir}/${name}";
      relPath = strings.removePrefix "${root}/" absPath;
      dst = strings.removeSuffix ".nix" relPath;
    in {
      inherit dst;
      src = self.lib.yaml.write absPath {
        inherit pkgs;
        name = dst;
        # Additional manifest params:
        inherit cluster;
        k = self.lib.kubernetes;
        v = cluster.versions;
      };
    };

    # Create a symbolic link to a generated source file.
    # Used for generating a symlink tree containing all manifests.
    copyYAML = {
      dst,
      src,
    }: let
      output = "$out/${dst}";
    in ''
      mkdir --parents "$(dirname "${output}")"
      cp "${src}" "${output}"
    '';

    # Finally combine all elements into a symlink tree.
    manifests-dir = pkgs.stdenv.mkDerivation {
      name = "manifests";
      phases = ["installPhase"];
      nativeBuildInputs = with pkgs; [fluxcd];
      installPhase = strings.concatStringsSep "\n" (map copyYAML srcs);
    };

    # OCI tar archive containing all manifests, used as build output.
    manifests-oci = pkgs.stdenv.mkDerivation (finalAttrs: {
      name = "manifests.tar.gz";

      src = manifests-dir;
      phases = ["installPhase"];
      nativeBuildInputs = with pkgs; [fluxcd];
      installPhase = ''
        flux build artifact --path="$src" --output="$out"
      '';
    });

    # FluxCD YAML manifests, extracted from the OCI artifact.
    manifests-yaml = pkgs.stdenv.mkDerivation (finalAttrs: {
      name = "manifests-yaml";

      src = manifests-oci;
      phases = ["installPhase"];
      nativeBuildInputs = with pkgs; [gnutar];
      installPhase = ''
        mkdir --parents "$out"
        tar --directory="$out" --file="$src" --extract --gzip
      '';
    });
  in {
    devenv.shells.default.env.MANIFESTS = manifests-dir;

    packages = {
      inherit manifests-oci manifests-yaml;
      default = manifests-yaml;
    };

    apps = let
      deploy = let
        artifactURI = with cluster.github; "oci://${registry}/${owner}/${repository}:latest";
      in {
        type = "app";
        program = pkgs.writeShellApplication {
          name = "deploy";
          runtimeInputs = with pkgs; [coreutils fluxcd git];
          text = ''
            TEMP_DIR="$(mktemp --directory)"
            cp --recursive "${manifests-oci}"/* "$TEMP_DIR"
            chmod --recursive +w "$TEMP_DIR"
            flux push artifact "${artifactURI}" \
              --path="$TEMP_DIR" \
              --source="$(git config --get remote.origin.url)" \
              --revision="$(git rev-parse --abbrev-ref HEAD)@sha1:$(git rev-parse HEAD)" \
              --reproducible
            rm --recursive --force "$TEMP_DIR"
          '';
        };
      };
    in {
      inherit deploy;
      default = deploy;
    };
  };
}
