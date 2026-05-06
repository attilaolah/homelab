# PKI

## Chain

TLS uses a three-layer chain:

- Root CA: `tls-ca/ca.{crt,key}` is a shared Clan var. `ca.key` is secret and `deploy = false`; it is only used locally for signing TPM intermediates. `ca.crt` is public and is added to the system trust store on every machine.
- TPM intermediate CA: each TPM-backed machine has `tpm/ca.{crt,key}`. `ca.key` is a TPM 1.2 key blob generated on that machine and deployed back to that same machine as `/run/secrets/vars/tpm/ca.key`. `ca.crt` is signed by the root with `CA:true,pathlen:0`, so it cannot sign another CA.
- Leaf TLS certificates: `issue-tls-certificate.service` creates `/run/pki/tls/tls.{crt,key}`. The key and CSR are generated in RAM, the cert is signed by the TPM intermediate, and only the final leaf key/cert live under `/run`.

No CA private key material is stored as a normal on-disk private key on the machine. The root key is a non-deployed Clan secret; the intermediate key is a TPM-bound blob; leaf material is ephemeral.

## Onboard TPM 1.2 Machine

Start by tagging the machine for TPM 1.2 bootstrap:

```nix
tpm12-bootstrap = ["new-machine"];
```

Deploy this first. The bootstrap tag installs `tcsd`, TPM device udev rules, and the non-deployed owner-auth Clan secret. It does not declare `tpm/ca.{key,crt}`, so it is safe before the machine has a TPM CA.

Set up the TPM manually:

1. Enable, activate, and clear the TPM in firmware.
2. Boot NixOS.
3. Ensure `tcsd` is running.
4. Take ownership if needed:

```sh
nix shell nixpkgs#tpm-tools -c tpm_takeownership --srk-well-known
```

If TPM commands fail with disabled/ownership errors, fix the TPM state in firmware first. Some firmware requires `enable, activate, clear, enable, activate` rather than only `clear`.

## Generate Intermediate Key

Run this on the target machine:

```sh
cd /var/lib/pki/tpm
nix shell nixpkgs#simple-tpm-pk11 nixpkgs#opensc nixpkgs#libp11 nixpkgs#openssl
stpm-keygen -o ca.key
```

Verify the TPM key:

```sh
echo test >/tmp/tpm-sign-test.txt
stpm-sign -k /var/lib/pki/tpm/ca.key -f /tmp/tpm-sign-test.txt >/tmp/tpm-sign-test.sig
ls -l /var/lib/pki/tpm/ca.key /tmp/tpm-sign-test.sig
```

## Create CSR

Still on the target machine:

```sh
machine="$(hostname)"
uri='pkcs11:id=%31%31%31%31;manufacturer=simple-tpm-pk11%20manufacturer;model=model;object=simple-tpm-private-key;serial=serial;token=Simple-TPM-PK11%20token;type=private'
engine="$(nix eval --raw nixpkgs#libp11.outPath)/lib/engines/pkcs11.so"
module="$(nix eval --raw nixpkgs#simple-tpm-pk11.outPath)/lib/libsimple-tpm-pk11.so.0.0.0"

cat >/tmp/simple-tpm-pk11.conf <<EOF
key /var/lib/pki/tpm/ca.key
EOF

cat >/tmp/openssl-pkcs11.cnf <<EOF
openssl_conf = openssl_init

[openssl_init]
engines = engine_section

[engine_section]
pkcs11 = pkcs11_section

[pkcs11_section]
engine_id = pkcs11
dynamic_path = $engine
MODULE_PATH = $module
init = 0
EOF

OPENSSL_CONF=/tmp/openssl-pkcs11.cnf \
SIMPLE_TPM_PK11_CONFIG=/tmp/simple-tpm-pk11.conf \
  openssl req \
    -new \
    -engine pkcs11 \
    -keyform engine \
    -key "$uri" \
    -subj "/CN=TLS CA: $machine.dorn.haus" \
    -out /var/lib/pki/tpm/ca.csr
```

Copy the CSR to the local workstation:

```sh
machine=todo
clan ssh "$machine" -c cat /var/lib/pki/tpm/ca.csr >"/tmp/$machine-tpm-ca.csr"
```

## Sign Intermediate

Run locally, from the repo:

```sh
machine=todo
umask 077

clan vars get "$machine" tls-ca/ca.key > /tmp/tls-root-ca.key

cat >/tmp/tpm-ca.ext <<EOF
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

openssl x509 \
  -req \
  -in "/tmp/$machine-tpm-ca.csr" \
  -CA vars/shared/tls-ca/ca.crt/value \
  -CAkey /tmp/tls-root-ca.key \
  -CAcreateserial \
  -out "/tmp/$machine-tpm-ca.crt" \
  -days 1825 \
  -sha256 \
  -extfile /tmp/tpm-ca.ext

rm -f /tmp/tls-root-ca.key vars/shared/tls-ca/ca.crt/value.srl
```

Verify:

```sh
openssl verify -CAfile vars/shared/tls-ca/ca.crt/value "/tmp/$machine-tpm-ca.crt"
openssl x509 -in "/tmp/$machine-tpm-ca.crt" -noout -subject -issuer -dates -text |
  rg 'Subject:|Issuer:|CA:TRUE|Path Length|Key Usage'
```

## Store Clan Vars

Copy the TPM key blob from the target and store both files:

```sh
machine=todo
mkdir -p "/tmp/$machine-tpm"

clan ssh "$machine" -c cat /var/lib/pki/tpm/ca.key >"/tmp/$machine-tpm/ca.key"
cp "/tmp/$machine-tpm-ca.crt" "/tmp/$machine-tpm/ca.crt"

clan vars set "$machine" tpm/ca.key <"/tmp/$machine-tpm/ca.key"
clan vars set "$machine" tpm/ca.crt <"/tmp/$machine-tpm/ca.crt"
clan vars fix "$machine"
```

`clan vars fix` is required when `tpm/ca.key` has `deploy = true`; it grants the target machine access to decrypt the deployed secret.

## Deploy

Only move the machine from `tpm12-bootstrap` to `tpm12` after `tpm/ca.key` and `tpm/ca.crt` exist:

```nix
tpm12 = ["new-machine"];
tpm12-bootstrap = [];
```

If a machine is tagged with full `tpm12` before those vars exist, `clan m update` may try to run the empty `tpm` generator and fail with:

```text
did not generate a file for 'ca.crt'
```

Deploy:

```sh
clan m update --build-host localhost "$machine"
```

Expected paths:

```text
/var/lib/pki/tpm/ca.key -> /run/secrets/vars/tpm/ca.key
/var/lib/pki/tpm/ca.crt -> /nix/store/...-tpm_ca.crt
/run/pki/tls/tls.key
/run/pki/tls/tls.crt
```

Start or inspect leaf issuance:

```sh
clan ssh "$machine" -c systemctl start issue-tls-certificate.service
clan ssh "$machine" -c systemctl status issue-tls-certificate.service
clan ssh "$machine" -c systemctl list-timers issue-tls-certificate.timer
clan ssh "$machine" -c nix shell nixpkgs#openssl -c openssl x509 -in /run/pki/tls/tls.crt -noout -subject -issuer -dates
```

The leaf certificate is valid for 8 days. The timer refreshes every 2 days with jitter, leaving time for manual repair if renewal fails.
