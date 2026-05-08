{
  clan-core,
  intermediateCaExt,
}: final: _prev: let
  inherit (final.stdenv.hostPlatform) system;
in {
  tpm-tls-sign = final.writeShellApplication {
    name = "tpm-tls-sign";
    runtimeInputs = [
      clan-core.packages.${system}.clan-cli
      final.coreutils
      final.gitMinimal
      final.openssl
    ];
    text = ''
      set -euo pipefail

      if [[ $# -ne 1 ]]; then
        echo "usage: tpm-tls-sign <machine>" >&2
        exit 2
      fi

      machine=$1
      work="$(mktemp -d "/tmp/tpm-tls-sign-$machine.XXXXXX")"
      root_key="$work/root-ca.key"
      csr="$work/ca.csr"
      crt="$work/ca.crt"
      key="$work/ca.key"
      serial="$work/ca.srl"

      repo="''${CLAN_DIR:-$(git rev-parse --show-toplevel)}"
      root_crt="$repo/vars/shared/tls-ca/ca.crt/value"
      if [[ ! -s "$root_crt" ]]; then
        echo "missing root CA certificate: $root_crt" >&2
        exit 1
      fi

      cleanup() {
        rm -f "$root_key"
      }
      trap cleanup EXIT

      # Avoid PTY line-ending conversion while fetching files through clan ssh.
      clan ssh "$machine" -c base64 -w0 /var/lib/pki/tpm/ca.csr |
        base64 -d > "$csr"
      clan ssh "$machine" -c base64 -w0 /var/lib/pki/tpm/ca.key |
        base64 -d > "$key"

      clan vars get "$machine" tls-ca/ca.key > "$root_key"

      openssl x509 \
        -req \
        -in "$csr" \
        -CA "$root_crt" \
        -CAkey "$root_key" \
        -CAserial "$serial" \
        -CAcreateserial \
        -out "$crt" \
        -days 1825 \
        -sha256 \
        -extfile ${intermediateCaExt}

      openssl verify -CAfile "$root_crt" "$crt"

      clan vars set "$machine" tpm/ca.key < "$key"
      clan vars set "$machine" tpm/ca.crt < "$crt"
      clan vars fix "$machine"

      echo "stored tpm/ca.key and tpm/ca.crt for $machine"
      echo "temporary files kept in $work"
    '';
  };
}
