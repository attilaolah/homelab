{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  common = import ../openbao_common.nix {inherit config inputs lib;};
  inherit (common) domain hostName inventory tls;
  clusterNodes = inventory.tags.openbao or [];
  clientNodes = inventory.tags.openbao_client or [];
  hostIp = inventory.machines.${hostName}.ip;
  apiName = "${hostName}.node.${domain}";
  clusterName = "${hostName}.node.${domain}";
  peerNodes = lib.filter (node: node != hostName) clusterNodes;
  peerJoins =
    lib.concatMapStringsSep "\n" (node: ''
      retry_join {
          leader_api_addr = "https://${node}.node.${domain}:8200"
          leader_tls_servername = "${node}.node.${domain}"
          leader_ca_cert_file = "${tls.ca}"
          leader_client_cert_file = "${tls.certificate}"
          leader_client_key_file = "${tls.key}"
      }
    '')
    peerNodes;
  clusterSources = lib.concatStringsSep ", " (map (node: inventory.machines.${node}.ip) clusterNodes);
  clientSources = lib.concatStringsSep ", " (map (node: inventory.machines.${node}.ip) clientNodes);
  validateTls = pkgs.writeShellApplication {
    name = "openbao-validate-tls";
    runtimeInputs = with pkgs; [coreutils gnugrep openssl];
    text = ''
      set -euo pipefail

      ca=$1
      certificate=$2
      key=$3
      api_name=$4
      cluster_name=$5

      test -r "$ca"
      test -r "$certificate"
      test -r "$key"
      openssl verify -purpose sslserver -CAfile "$ca" -verify_hostname "$api_name" "$certificate" >/dev/null
      openssl verify -purpose sslserver -CAfile "$ca" -verify_hostname "$cluster_name" "$certificate" >/dev/null
      openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL client : Yes'
      openssl x509 -in "$certificate" -noout -purpose | grep -Fq 'SSL server : Yes'
      openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$api_name"
      openssl x509 -in "$certificate" -noout -ext subjectAltName | grep -Fq "DNS:$cluster_name"

      certificate_public_key=$(openssl x509 -in "$certificate" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | openssl dgst -sha256)
      key_public_key=$(openssl pkey -in "$key" -pubout -outform DER | openssl dgst -sha256)
      test "$certificate_public_key" = "$key_public_key"
    '';
  };
  openbaoConfiguration = pkgs.writeText "openbao.hcl" ''
        api_addr = "https://${apiName}:8200"
        cluster_addr = "https://${clusterName}:8201"
        cluster_name = "homelab-openbao"
        disable_mlock = true
        ui = false

        listener "tcp" {
          address = "${hostIp}:8200"
            cluster_address = "${hostIp}:8201"
            tls_ca_file = "${tls.ca}"
            tls_cert_file = "${tls.certificate}"
            tls_key_file = "${tls.key}"
          tls_min_version = "tls13"
          tls_require_and_verify_client_cert = true
        }

        storage "raft" {
          path = "/var/lib/openbao"
          node_id = "${hostName}"

        ${peerJoins}
        }
  '';
  clientProvisioning =
    lib.concatMapStringsSep "\n\n" (node: ''
      bao policy write caddy-${node} - <<'POLICY'
      path "gocryptfs/data/${node}/mount-key" {
        capabilities = ["read"]
      }
      POLICY

      # Roles trust the TPM cluster CA and constrain the DNS SAN. This avoids
      # copying a Caddy private key or public certificate to a server.
      bao write auth/cert/certs/caddy-${node} \
        certificate=@"${tls.ca}" \
        allowed_dns_sans="${node}.node.${domain}" \
        policies=caddy-${node} \
        token_ttl=1h \
        token_max_ttl=4h

      if ! bao kv get -mount=gocryptfs ${node}/mount-key >/dev/null 2>&1; then
        ${node}_key=$(openssl rand -base64 48)
        bao kv put -mount=gocryptfs ${node}/mount-key key="$${node}_key"
      fi
    '')
    clientNodes;
  bootstrap = pkgs.writeShellApplication {
    name = "openbao-bootstrap";
    runtimeInputs = with pkgs; [coreutils gnugrep jq openbao openssl];
    text = ''
      set -euo pipefail

        export BAO_ADDR="https://${apiName}:8200"
        export BAO_CACERT="${tls.ca}"
        export BAO_CLIENT_CERT="${tls.certificate}"
        export BAO_CLIENT_KEY="${tls.key}"
      : "''${BAO_TOKEN:?/run/openbao/bootstrap.env must define BAO_TOKEN}"

      bao status >/dev/null

      if ! bao auth list -format=json | jq -e 'has("cert/")' >/dev/null; then
        bao auth enable cert
      fi

      if ! bao secrets list -format=json | jq -e '."gocryptfs/".type == "kv"' >/dev/null; then
        bao secrets enable -path=gocryptfs -version=2 kv
      fi

      ${clientProvisioning}
    '';
  };
in
  lib.mkMerge [
    common.module

    {
      networking.firewall.extraInputRules = lib.mkAfter ''
        ip saddr { ${clusterSources} } tcp dport { 8200, 8201 } accept
        ip saddr { ${clientSources} } tcp dport 8200 accept
      '';

      users = {
        groups.openbao = {};
        users.openbao = {
          isSystemUser = true;
          group = "openbao";
        };
      };

      systemd.services.openbao = {
        description = "OpenBao Raft server";
        after = ["network-online.target" "issue-tls-certificate.service"];
        requires = ["issue-tls-certificate.service"];
        wants = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          User = "openbao";
          Group = "openbao";
          SupplementaryGroups = ["tls"];
          StateDirectory = "openbao";
          StateDirectoryMode = "0700";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = ["/var/lib/openbao"];
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStartPre = "${lib.getExe validateTls} ${tls.ca} ${tls.certificate} ${tls.key} ${apiName} ${clusterName}";
          ExecStart = "${lib.getExe pkgs.openbao} server -config=${openbaoConfiguration}";
        };
      };
    }

    # This is intentionally only installed on iris and has no WantedBy. An
    # operator supplies a short-lived root token after init/unseal, then starts
    # it explicitly. It can safely be rerun for certificate rotation.
    (lib.mkIf (hostName == "iris") {
      systemd.services.openbao-provision = {
        description = "Provision OpenBao Caddy certificate-auth access";
        after = ["network-online.target" "openbao.service"];
        requires = ["openbao.service"];
        unitConfig.ConditionPathExists = "/run/openbao/bootstrap.env";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          UMask = "0077";
          EnvironmentFile = "/run/openbao/bootstrap.env";
          ExecStart = lib.getExe bootstrap;
        };
      };
    })
  ]
