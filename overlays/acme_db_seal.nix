{clan-core}: final: _prev: let
  inherit (final.stdenv.hostPlatform) system;
in {
  acme-db-seal = final.writeShellApplication {
    name = "acme-db-seal";
    runtimeInputs = [
      clan-core.packages.${system}.clan-cli
      final.coreutils
      final.gitMinimal
    ];
    text = ''
      set -euo pipefail

      if [[ $# -ne 1 ]]; then
        echo "usage: acme-db-seal <machine>" >&2
        exit 2
      fi

      machine=$1
      work="$(mktemp -d "/tmp/acme-db-seal-$machine.XXXXXX")"
      sealed="$work/key.sealed"

      cleanup() {
        rm -rf "$work"
      }
      trap cleanup EXIT

      # shellcheck disable=SC2016
      clan ssh "$machine" -c bash -c '
        set -euo pipefail
        tmp="$(mktemp -d /run/pki/acme-db-seal.XXXXXX)"
        cleanup_remote() {
          rm -rf "$tmp"
        }
        trap cleanup_remote EXIT

        head -c 48 /dev/urandom | base64 -w0 > "$tmp/key"
        tpm_sealdata -z -i "$tmp/key" -o "$tmp/key.sealed"
        # Avoid PTY line-ending conversion while fetching files through clan ssh.
        base64 -w0 "$tmp/key.sealed"
      ' | base64 -d > "$sealed"

      clan vars set "$machine" acme-db/key.sealed < "$sealed"
      clan vars fix "$machine"

      echo "stored acme-db/key.sealed for $machine"
    '';
  };
}
