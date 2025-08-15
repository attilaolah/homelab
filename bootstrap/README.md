## Custom Domain (one-time)

To use a custom domain, there is a one-time bootstrapping procedure to go through.

### 1. Get a domain

I'll be going with `dorn.haus`, but any domain should do.

### 2. Register with Cloudflare

I'll be using Cloudflare services later on, most notably DNS, so I always start by registering the domain with
Cloudflare.

An additional perk with Cloudflare is the free email forwarding of wildcard addresses, allowing incoming emails without
having to register with an email provider or manage an exchange server.

But the main reason for registering early is to get an SSL certificate. CGNAT occasionally causes incoming traffic on
port 80 to be blocked, making it impossible to get/renew certificates using Certbot with the HTTP challenge.

### 3. Get a temporary Let's Encrypt certificate for the domain

An easy way to get started is to manually get an initial certificate:

```bash
certbot certonly --preferred-challenges dns --manual -d dorn.haus
```

Then manually add & remove the TXT record in the Cloudflare UI.

I then set up a simple Nginx reverse-proxy and NAT port 443. This will be needed to serve the OIDC authorization flow
via Keycloak (next step).

### 4. Start a temporary Keycloak server

Fire up a Keycloak development server using Podman to create an initial user, `attila@dorn.haus`. I do this at home
while NATing outbound traffic and verifying that the Let's Encrypt certificate is still functional.

```bash
export PASSWORD="$(openssl rand -base64 18)"
echo "Keycloak temporary admin password: $PASSWORD"
podman run \
  --name keycloak \
  -p 8443:8443 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD="$PASSWORD" \
  -v /path/to/certs:/etc/tls:z \
  quay.io/keycloak/keycloak start \
  --proxy-headers=forwarded \
  --hostname=https://dorn.haus/keycloak \
  --https-certificate-file=/etc/tls/cert.pem \
  --https-certificate-key-file=/etc/tls/privkey.pem \
  --log-level=INFO \
  --verbose
```

Next, configure WebFinger in Nginx (see `manifests/keycloak/well-known/app/config-map.yaml.nix`). Create a new Keycloak
realm, add a user (e.g. `attila@dorn.haus`), and add the Tailscale client. The Tailscale Client ID & secret will be
needed when connecting.

Once connected, we can sign in to Tailscale using Keycloak as the OIDC provider, and create a personal tailnet for our
domain, for free.

*IMPORTANT:* After creating a Tailscale org, a backup user should be added, in case the Keycloak client gets lost or
corrupted. Alternatively, a hardware security key can be added as a login method for the admin user.

---

## Talos

Talos can be bootstrapped more or less using `talos:bootstrap`. It installs Talos, Cilium and the Kubelet CSR approver.

## Flux + Secrets

Prerequisites:

- API server (KAS), controller-manager and scheduler should all be running.
- Cilium should be installed and running, `cilium status` should be all green.

The Flux operator and instance can be installed with `task flux:bootstrap`. This will also install the External Secrets
operator and inject its initial secret from SOPS secrets in this repo. Further secrets will be created by the operator,
including the image pull credentials needed to fetch Flux artifacts.

All secrets are managed by the operator (ESO), except for the GCP service account key used by ESO itself. The key is
stored in `gcp-secrets-service-account.sops.json` in the repo.

## ZFS

On Talos nodes, ZFS pools are created manually (for now), from within a privileged Alpine container, using `nsenter` to
enter the host init namespace from the pod:

```sh
nsenter --target 1 --mount --ipc --net --pid chroot /host \
  zpool create -f -o ashift=12 -m /var/zfs/tank tank /dev/sdb
```

The `ashift=12` above is for HDDs with 4K sectors. To verify:

```sh
nsenter --target 1 --mount --ipc --net --pid chroot /host \
  zpool list
```

On Alpine nodes the pools are created using the Ansible playbooks with tags `zfs`.
