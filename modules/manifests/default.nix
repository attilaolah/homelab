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
            cp --recursive "${manifests-yaml}"/* "$TEMP_DIR"
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

      expand = {
        type = "app";
        program = pkgs.writeShellApplication {
          name = "deploy";
          runtimeInputs = with pkgs; [coreutils yq];
          text = ''
            find "${manifests-yaml}" -name helm-release.yaml -print0 |
              while IFS= read -r -d "" helm_release
              do
              repo_kind="$(yq < "$helm_release" --raw-output .spec.chart.spec.sourceRef.kind)"
              if [[ "$repo_kind" == "GitRepository" ]]; then
                # TODO: Support Git Helm repositories.
                continue
              fi

              app_dir="$(dirname "$helm_release")"
              release_dir="$(dirname "$app_dir")"
              namespace_dir="$(dirname "$release_dir")"
              namespace="$(basename "$namespace_dir")"

              # Sanity check: make sure a namespace manifest is generated.
              namespace_name="$(yq < "$namespace_dir/namespace.yaml" --raw-output .metadata.name)"
              if [[ "$namespace_name" != "$namespace" ]]; then
                echo >&2 "ERROR: while processing release $helm_release:"
                echo >&2 "ERROR: unexpected namespace: $namespace_name != $namespace"
                exit 1
              fi

              # Sanity check: make sure the release name matches directory name.
              release_name="$(basename "$release_dir")"
              release="$(yq < "$helm_release" --raw-output .metadata.name)"
              if [[ "$release_name" != "$release" ]]; then
                echo >&2 "ERROR: while processing release $helm_release:"
                echo >&2 "ERROR: unexpected release: $release_name != $release"
                exit 1
              fi

              repo_url="$(
                cat "${manifests-yaml}/flux-system"/*-repository.yaml |
                yq --raw-output '
                  select(.kind=='"$(yq < "$helm_release" .spec.chart.spec.sourceRef.kind)"') |
                  select(.metadata.namespace=='"$(yq < "$helm_release" .spec.chart.spec.sourceRef.namespace)"') |
                  select(.metadata.name=='"$(yq < "$helm_release" .spec.chart.spec.sourceRef.name)"') |
                  .spec.url
                '
              )"
              chart="$(yq < "$helm_release" --raw-output .spec.chart.spec.chart)"
              version="$(yq < "$helm_release" --raw-output .spec.chart.spec.version)"

              helm_flags=(
                "--namespace=$namespace"
                "--version=$version"
              )
              if [[ "$repo_url" == "oci://"* ]]; then
                chart="$repo_url/$chart"
              else
                helm_flags+=("--repo=$repo_url")
              fi

              while IFS= read -r config_map; do
                while IFS= read -r values_yaml; do
                  helm_flags+=("--values=$app_dir/$values_yaml")
                done < <(yq < "$app_dir/kustomization.yaml" --raw-output '
                  .configMapGenerator[] |
                  select(.name=='"$config_map"') |
                  .files[]
                ')
              done < <(yq < "$helm_release" '
                .spec.valuesFrom[] |
                select(.kind=="ConfigMap") |
                .name
              ')

              echo "Running: helm template $release $chart ..."
              helm template "$release" "$chart" "''${helm_flags[@]}" \
                > "manifests/$namespace/$release/app/helm-generated.yaml"
            done
          '';
        };
      };
    };
  };
}
