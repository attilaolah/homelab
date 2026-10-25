# OpenBao

`iris`, `inga`, and `hoya` run the three-member `homelab-openbao` Raft
cluster. The API listener is TLS 1.3 with mandatory client certificates on
port 8200; Raft traffic on port 8201 has the same requirement. The firewall
accepts those ports only from the three cluster members, plus API requests from
the OpenBao client machines (`aria` and `ilex`). Use an SSH tunnel to a cluster member
for any operator access instead of widening the firewall.

The inventory separates those responsibilities: `openbao = [ iris inga hoya ]`
installs the Raft server and the `openbao-provision-cryptfs` operator command,
while `openbao_client = [ aria ilex ]` installs only generic mTLS identity
validation. The shared `openbao/common.nix` module provides their common PKI
material and root trust; clients never run OpenBao, and servers never install
the client identity validator.

## Runtime PKI

Both OpenBao tags have a hard dependency on the repository's TLS issuer and
its `issue-tls-certificate.service`; configuration evaluation fails if that
issuer is absent. There is no manual `/run/pki/tls` artifact prerequisite.

The existing certificate issuer automatically creates and renews, on every participating host,
`/run/pki/tls/tls.crt` and `/run/pki/tls/tls.key` with the existing TPM key
protection. OpenBao servers, Raft retry joins, the operator command, and the
client identity validator use those files directly. They use the canonical shared
`tls-ca/ca.crt` Clan variable path directly for cluster trust; no CA copy,
private-key copy, or OpenBao-specific TLS alias is created.

The OpenBao service reads its local key through the existing `tls` group.
`openbao-client-identity.service` runs after certificate issuance with a
dynamic unprivileged user in that group to prove that a client host's local
certificate identity is usable. It is not ordered around, or coupled to, a
particular secret consumer.

Before OpenBao starts, validation requires CA chaining, a matching private key,
both server and client EKUs, and the configured API and cluster DNS SANs. It
trusts only the shared root and supplies the host TPM intermediate explicitly,
because OpenSSL does not treat the appended certificate in `tls.crt` as an
untrusted issuer automatically. The client validator uses that intermediate
when present and retains direct-root validation for ACME clients. It checks CA
chaining, key matching, client EKU, and that host's DNS SAN. Raft retry joins
set the expected leader TLS server name explicitly.

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

Store the resulting recovery material with the declared shared
`openbao-init` Clan generator. Its exact secret variable IDs are:

- `openbao-init/initial-root-token`
- `openbao-init/unseal-share-1`
- `openbao-init/unseal-share-2`
- `openbao-init/unseal-share-3`
- `openbao-init/unseal-share-4`
- `openbao-init/unseal-share-5`

From a local interactive terminal in this repository, set each value once
against any OpenBao server (the commands below use `iris`). The pinned Clan
CLI syntax is `clan vars set <machine> <var-id>`; with a TTY it reads a hidden
multiline value from the prompt rather than a command-line argument. Paste one
value at each prompt and finish the multiline input as instructed by the CLI:

```sh
nix develop . -c clan vars set iris openbao-init/initial-root-token
nix develop . -c clan vars set iris openbao-init/unseal-share-1
nix develop . -c clan vars set iris openbao-init/unseal-share-2
nix develop . -c clan vars set iris openbao-init/unseal-share-3
nix develop . -c clan vars set iris openbao-init/unseal-share-4
nix develop . -c clan vars set iris openbao-init/unseal-share-5
```

The generator is shared only by `iris`, `inga`, and `hoya`, and every file has
`deploy = false`: the values are encrypted in the local Clan vars store but
are never made available to any host. Do not put a value in a shell command,
command substitution, or shell history. Unseal `iris`,
`inga`, and `hoya` with a threshold number of shares. Raft peers use their
configured retry joins after unseal; verify with `bao operator raft list-peers`
from a root, mTLS-authenticated shell. Do not configure auto-unseal until a
separately reviewed hardware key-management design exists.

## Post-unseal cryptfs provisioning

After the cluster has been initialized and unsealed, run the repeatable
`openbao-provision-cryptfs` command on any `openbao` server for each approved
`openbao_client` host. The command uses that server's local cluster mTLS
certificate and the canonical cluster CA. It requires exactly one approved
host argument and refuses all other host names.

The command uses an inherited nonempty `BAO_TOKEN` when it is available.
Otherwise, in an interactive terminal it securely prompts for the token with
hidden input. Run it directly on an OpenBao server without putting the token in
a command line, a file, or shell history:

```sh
sudo -i
openbao-provision-cryptfs aria
openbao-provision-cryptfs ilex
exit
```

For a non-interactive remote invocation, the command reads exactly one token
line from standard input. For example, read the token locally with hidden input
and pipe it through `clan ssh`; the token is not an argument to either command:

```sh
IFS= read -r -s -p 'OpenBao root token: ' BAO_TOKEN
printf '\n'
printf '%s\n' "$BAO_TOKEN" | nix develop . -c clan ssh iris -- sudo openbao-provision-cryptfs aria
unset BAO_TOKEN
```

This keeps the token out of persistent storage. The exported value is
temporary and is needed only so the `bao` subprocesses can authenticate. Do
not run the command before initialization and unseal, and do not use a
recovered token in a shell command or command substitution.

Provisioning enables certificate authentication, creates the generic KV v2
mount `cryptfs`, and creates a unique random key at `cryptfs/<host>/key` only
when that key is absent. It also writes the exact per-host policy and
certificate role on every invocation, making role updates and interrupted
provisioning safe to rerun without replacing an existing key.

Each role trusts the shared cluster CA but accepts only its own DNS SAN
(`aria.node.haus` or `ilex.node.haus`). Consequently, a certificate from one
client host cannot obtain the other host's token. The policies allow only
these KV v2 data paths:

| Role           | Allowed path            |
| -------------- | ----------------------- |
| `cryptfs-aria` | `cryptfs/data/aria/key` |
| `cryptfs-ilex` | `cryptfs/data/ilex/key` |

They do not grant list, write, delete, or access to the other host's key. The
cryptfs keys exist only in OpenBao KV; they are never Clan secrets. Future
consumers must authenticate with their local `openbao-client` identity and
read their exact `cryptfs/data/<host>/key` path. This configuration does not
yet implement secret retrieval or any cryptfs mount.
