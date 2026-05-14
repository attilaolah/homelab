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
tpm12_bootstrap = ["new-machine"];
```

Deploy this first. The bootstrap tag installs `tcsd`, TPM device udev rules, the `tpm-tls-bootstrap` helper, and the non-deployed owner-auth Clan secret. It does not declare `tpm/ca.{key,crt}`, so it is safe before the machine has a TPM CA.

Fetch the owner password locally when a TPM command prompts for it:

```sh
machine=todo
clan vars get "$machine" tpm-owner-auth/owner-auth
```

Set up the TPM manually:

1. Enable, activate, and clear the TPM in firmware.
2. Boot NixOS.
3. Ensure `tcsd` is running.
4. Take ownership if needed:

```sh
nix shell nixpkgs#tpm-tools -c tpm_takeownership --srk-well-known
```

If TPM commands fail with disabled/ownership errors, fix the TPM state in firmware first. Some firmware requires `enable, activate, clear, enable, activate` rather than only `clear`.

## Generate Intermediate Key And CSR

Run this on the target machine:

```sh
tpm-tls-bootstrap
```

This writes:

```text
/var/lib/pki/tpm/ca.key
/var/lib/pki/tpm/ca.csr
```

The command refuses to overwrite an existing `ca.key`.

## Sign And Store Intermediate

Move the machine from `tpm12_bootstrap` to `tpm12` locally before signing, but do not deploy yet:

```nix
tpm12 = ["new-machine"];
tpm12_bootstrap = [];
```

This makes Clan know about the `tpm/ca.{key,crt}` vars while the target still has the bootstrap tooling from its previous deployment.

Run locally, from this repo's dev shell:

```sh
machine=todo
tpm-tls-sign "$machine"
```

This fetches `/var/lib/pki/tpm/ca.{key,csr}`, signs the CSR with the offline root, stores `tpm/ca.{key,crt}` as Clan vars, verifies the cert, and runs `clan vars fix "$machine"`.

## Deploy

Only deploy full `tpm12` after `tpm/ca.key` and `tpm/ca.crt` exist:

```nix
tpm12 = ["new-machine"];
tpm12_bootstrap = [];
```

If a machine is deployed with full `tpm12` before those vars exist, `clan m update` may try to run the empty `tpm` generator and fail with:

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

## Provision ACME EAB Client

Non-TPM machines use ACME. EAB credentials are only bootstrap material. The durable client credential is the ACME account state stored as Clan secrets:

```text
acme-accounts/<acme-host>/account.json
acme-accounts/<acme-host>/account.key
```

They request certificates with TLS-ALPN-01. Port 443 must be free while `issue-tls-certificate.service` runs. The issued leaf key and certificate still live under `/run`.

The order matters because Clan initialises missing deployable vars during unrelated machine updates. Do not add the new client directly to `acme_client` before provisioning.

ACME server firewall rules are generated from `acme_client` and `acme_client_bootstrap`. After changing either tag, update the ACME servers so the new client can reach the ACME port.

1. Update the ACME servers after adding the new client to `acme_client_bootstrap`.
2. Add the new client to `acme_client_bootstrap` and deploy it. This installs `issue-tls-certificate.service` without declaring `acme-accounts/*` secrets.
3. The service is installed but not enabled in bootstrap mode. It stays idle until `acme-provision` injects temporary EAB credentials and starts it.
4. Move the client from `acme_client_bootstrap` to `acme_client` locally, but do not deploy yet. This makes Clan know about `acme-accounts/*` without pushing empty placeholders to the machine.
5. Run the provisioning helper:

```sh
machine=todo
for acme_host in acer hoya; do
  acme-provision "$acme_host" "$machine"
done
```

`acme-provision` targets one ACME endpoint at a time. It writes or replaces the client's EAB entry on the selected ACME server, copies the EAB credential into `/run/pki/acme/bootstrap-eab/<acme-host>` on the client, starts `issue-tls-certificate.service` with that endpoint pinned, captures Lego's generated account state, stores it as `acme-accounts/<acme-host>/*`, removes the temporary EAB files, and runs `clan vars fix "$machine"`.

6. Deploy the client again so both endpoint account states are managed by Clan.

The account state is tied to the ACME server database. If the ACME database is rebuilt from scratch, re-run provisioning for each ACME client.

When changing ACME endpoint hostnames, re-provision each ACME client for each endpoint. No automatic migration is provided.

## Encrypt ACME Server DB (TPM + gocryptfs)

ACME servers mount the Step CA database path `/var/lib/step-ca/db` through `gocryptfs`. The encrypted backing directory is `/var/lib/step-ca/db.crypt`.

The `gocryptfs` passphrase is sealed by the server TPM and stored as the deployable Clan secret:

```text
acme-db/key.sealed
```

For new ACME servers, use this order:

1. Add the machine to `tpm12` and deploy it.
2. Add the machine to `acme`, but do not deploy yet.
3. Generate and store the sealed DB key from this repo:

```sh
machine=todo
acme-db-seal "$machine"
```

Before deploying, verify the sealed key exists and is non-empty:

```sh
test "$(clan vars get "$machine" acme-db/key.sealed | wc -c)" -gt 0
```

If this check fails, re-run `acme-db-seal "$machine"` and check again.

4. Deploy the machine. This installs socket activation (`step-ca-proxy.socket`) and on-demand ACME services.
