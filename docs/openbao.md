# OpenBao

`iris`, `inga`, and `hoya` run the three-member `homelab-openbao` Raft
cluster. The API listener is TLS 1.3 with mandatory client certificates on
port 8200; Raft traffic on port 8201 has the same requirement. The firewall
accepts those ports only from the three cluster members, plus API requests from
the Caddy machines (`aria` and `ilex`). Use an SSH tunnel to a cluster member
for any operator access instead of widening the firewall.

The inventory separates those responsibilities: `openbao = [ iris inga hoya ]`
installs the Raft server and its explicit bootstrap unit, while
`openbao_client = [ aria ilex ]` installs only the Caddy mTLS identity
validation. The shared `openbao/common.nix` module provides their common PKI
material and root trust; clients never run OpenBao, and servers never install
the Caddy identity validator.

## Runtime PKI

Both OpenBao tags have a hard dependency on the repository's TLS issuer and
its `issue-tls-certificate.service`; configuration evaluation fails if that
issuer is absent. There is no manual `/run/pki/tls` artifact prerequisite.

The existing certificate issuer automatically creates and renews, on every participating host,
`/run/pki/tls/tls.crt` and `/run/pki/tls/tls.key` with the existing TPM key
protection. OpenBao servers, Raft retry joins, provisioning, and the Caddy-host
identity validator use those files directly. They use the canonical shared
`tls-ca/ca.crt` Clan variable path directly for cluster trust; no CA copy,
private-key copy, or OpenBao-specific TLS alias is created.

The OpenBao service reads its local key through the existing `tls` group. The
Caddy account is also in that group, and `openbao-client-identity.service` runs
as that account before Caddy to prove its local certificate identity is usable.
This prepares the identity for a future gocryptfs consumer; it does not add
Caddy TLS or gocryptfs work.

Before OpenBao starts, validation requires CA chaining, a matching private key,
both server and client EKUs, and the configured API and cluster DNS SANs. The
Caddy-host validator checks CA chaining, key matching, client EKU, and that
host's DNS SAN. Raft retry joins set the expected leader TLS server name
explicitly.

## First initialization and unseal

OpenBao initialization is intentionally not declarative. It creates recovery
material that is kept as a Clan cluster/shared secret, stored locally with
`deploy = false`, just like the shared TLS CA private key. The initial root
token and every unseal/recovery share must never be deployed to a host by
Clan, included in the Nix store, or committed to this repository. After the
runtime PKI material exists and the three services have started, perform
initialization once on `iris` as a console operator (or over an SSH tunnel).
Become root before setting the mTLS Bao environment:

```sh
sudo -i
export BAO_ADDR=https://iris.node.haus:8200
export BAO_CLIENT_CERT=/run/pki/tls/tls.crt
export BAO_CLIENT_KEY=/run/pki/tls/tls.key
bao operator init -key-shares=5 -key-threshold=3
```

Store the resulting five unseal/recovery shares and initial root token in the
locally stored Clan cluster/shared secrets using `deploy = false`; do not make
an additional host deployment. Unseal `iris`, `inga`, and `hoya` with the
threshold number of shares. Raft peers use their configured retry joins after
unseal; verify with `bao operator raft list-peers` from this root,
mTLS-authenticated shell. Do not configure auto-unseal until there is a
separately reviewed hardware key-management design.

## Post-unseal Caddy provisioning

The explicit `openbao-provision` unit on `iris` is the repeatable,
post-unseal-only bootstrap. It enables certificate auth, creates the KV v2
mount `gocryptfs`, creates a random value at each of
`aria/mount-key` and `ilex/mount-key` only if absent, and binds each Caddy host
to a separate role and policy.

Each role trusts the shared cluster CA but accepts only its own DNS SAN
(`aria.node.haus` or `ilex.node.haus`). Consequently, a certificate from one
Caddy host cannot obtain the other host's token. The policies allow only these
KV v2 data paths:

| Role         | Allowed path                    |
| ------------ | ------------------------------- |
| `caddy-aria` | `gocryptfs/data/aria/mount-key` |
| `caddy-ilex` | `gocryptfs/data/ilex/mount-key` |

They do not grant list, write, delete, or access to the other host's key. The
per-Caddy gocryptfs mount keys exist only in OpenBao KV; they are never Clan
secrets, including when a future gocryptfs consumer is added.

After unseal, the only exception to keeping the initial root token off hosts is
a temporary root-only `/run/openbao/bootstrap.env` on `iris`. Create it solely
to run the idempotent post-init provisioning unit. The provisioning service
runs as root so it can read the file; it is never exposed to the `openbao`
service account. From the root shell above, create the directory and file:

```sh
install -d -m 0700 -o root -g root /run/openbao
install -m 0600 /dev/null /run/openbao/bootstrap.env
printf '%s\n' 'BAO_TOKEN=PASTE_INITIAL_ROOT_TOKEN' > /run/openbao/bootstrap.env
systemctl start openbao-provision.service && rm -f /run/openbao/bootstrap.env
```

The `&&` removes the temporary file immediately only after a successful run.
Then leave the root shell:

```sh
exit
```

If provisioning fails, leave the file in place so the same idempotent unit can
be retried; remove it immediately after a successful retry. The file is a
manual, root-only runtime exception, not a Clan deployment, and is never
persisted by Nix. Certificate renewal is automatic; run this unit again only
to change a certificate-auth role or retry interrupted bootstrap. Existing KV
values are preserved by the idempotent provisioning step.

Future gocryptfs consumers must authenticate to `auth/cert/login` with their
local `openbao-client` identity and read the exact API path
`gocryptfs/data/<host>/mount-key`; they must not use AppRole or Clan secrets.
