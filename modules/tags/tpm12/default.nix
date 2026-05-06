{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.clan.core.vars.generators.tpm) files;
  inherit (config.networking) domain hostName;

  b = "ca";
  crt = "${b}.crt";
  key = "${b}.key";
  tpm = "/var/lib/pki/tpm";
  tls = "/run/pki/tls";

  commonName = "${hostName}.${domain}";
  subjectAltName = lib.concatMapStringsSep "," (dnsName: "DNS:${dnsName}") [hostName commonName];
  pkcs11Uri =
    "pkcs11:"
    + lib.concatStringsSep ";"
    (lib.mapAttrsToList (name: value: "${name}=${builtins.replaceStrings [" "] ["%20"] value}") {
      id = "%31%31%31%31";
      manufacturer = "simple-tpm-pk11 manufacturer";
      model = "model";
      object = "simple-tpm-private-key";
      serial = "serial";
      token = "Simple-TPM-PK11 token";
      type = "private";
    });

  certExt = pkgs.replaceVars ./templates/cert.ext.in {
    inherit subjectAltName;
  };
  opensslConf = pkgs.replaceVars ./templates/openssl.cnf.in {
    pkcs11Engine = "${pkgs.libp11}/lib/engines/pkcs11.so";
    pkcs11Module = "${pkgs.simple-tpm-pk11}/lib/libsimple-tpm-pk11.so.0.0.0";
  };
  reqConf = pkgs.replaceVars ./templates/req.cnf.in {
    inherit commonName subjectAltName;
  };
  simpleTpmPk11Conf = pkgs.replaceVars ./templates/simple-tpm-pk11.conf.in {
    caKey = "${tpm}/${key}";
  };
in {
  clan.core.vars.generators = {
    tpm-owner-auth = {
      files.owner-auth = {
        secret = true;
        deploy = false;
      };
      runtimeInputs = with pkgs; [xkcdpass];
      script = ''
        xkcdpass --numwords 6 --delimiter - --count 1 |
          tr -d "\n" > "$out/owner-auth"
      '';
    };

    tpm = {
      files = {
        "${key}" = {
          secret = true;
          deploy = true;
        };
        "${crt}" = {
          secret = false;
          deploy = false;
        };
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d ${tpm} 0700 root root - -"
      "L+ ${tpm}/${key} - - - - ${files.${key}.path}"
      "L+ ${tpm}/${crt} - - - - ${files.${crt}.path}"
    ];

    services.issue-tls-certificate = {
      description = "Issue short-lived TLS certificate from TPM CA";
      wantedBy = ["multi-user.target"];
      wants = ["tcsd.service" "systemd-tmpfiles-setup.service"];
      after = ["tcsd.service" "systemd-tmpfiles-setup.service"];
      path = with pkgs; [coreutils openssl];

      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        PrivateTmp = true;
      };

      script = ''
        set -euo pipefail

        work="$(mktemp -d /run/pki/tls-work.XXXXXX)"
        trap 'rm -rf "$work"' EXIT

        openssl genpkey \
          -algorithm EC \
          -pkeyopt ec_paramgen_curve:P-256 \
          -out "$work/tls.key"

        openssl req \
          -new \
          -key "$work/tls.key" \
          -out "$work/tls.csr" \
          -config ${reqConf}

        OPENSSL_CONF=${opensslConf} \
        SIMPLE_TPM_PK11_CONFIG=${simpleTpmPk11Conf} \
          openssl x509 \
            -req \
            -engine pkcs11 \
            -in "$work/tls.csr" \
            -CA ${tpm}/${crt} \
            -CAkeyform engine \
            -CAkey "${pkcs11Uri}" \
            -set_serial "0x$(openssl rand -hex 16)" \
            -out "$work/tls.crt" \
            -days 8 \
            -sha256 \
            -extfile ${certExt}

        install -d -m 0750 -o root -g tls ${tls}
        install -m 0640 -o root -g tls "$work/tls.key" ${tls}/tls.key.new
        install -m 0644 -o root -g tls "$work/tls.crt" ${tls}/tls.crt.new
        cat ${tpm}/${crt} >> ${tls}/tls.crt.new
        chown root:tls ${tls}/tls.crt.new
        chmod 0644 ${tls}/tls.crt.new
        mv -f ${tls}/tls.key.new ${tls}/tls.key
        mv -f ${tls}/tls.crt.new ${tls}/tls.crt
      '';
    };

    timers.issue-tls-certificate = {
      description = "Refresh short-lived TLS certificate";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "2d";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
  };

  services = {
    tcsd.enable = true;

    # Trousers/tcsd runs as user/group tss and needs access to TPM device nodes.
    udev.extraRules = ''
      SUBSYSTEM=="tpm", KERNEL=="tpm[0-9]*", GROUP="tss", MODE="0660"
      SUBSYSTEM=="tpmrm", KERNEL=="tpmrm[0-9]*", GROUP="tss", MODE="0660"
    '';
  };
}
