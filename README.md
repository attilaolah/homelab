# Home Kubernetes Cluster

> IPv6-friendly Kubernetes cluster running on commodity hardware in a locker (yes, an actual locker).

![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/attilaolah/homelab?labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)

## 📖 Overview

This repository contains Infrastructure as Code (IaC) and GitOps config files for managing my hobby cluster in the
basement. Inspired by popular repos like [toboshii/home-ops], with a few additional considerations:


- **🛠️ Unconventional hardware:** As much as I enjoy automating the software infrastructure, I also really like
  building custom hardware to power it all. I spend maybe half the time in front of the ⌨️ keyboard and half the time
  using 🪚🪛 power tools.
- **🌳 Low footprint:** All of the nodes are either old machines I am no longer using, or used machines I bought for
  next to nothing. Many use passive cooling, and there are a fair bit of x86 (mostly i686) CPUs involved.

---

## Custom Domain

To use a custom domain, there is a one-time bootstrapping procedure to go through.

### 1. Get a domain

I'll be going with `dorn.haus`, but any domain should do.

### 2. Register with Cloudflare

I'll be using Cloudflare services later on, most notably DNS, so I always start by registering the domain with
Cloudflare.

An additional perk with Cloudflare is the free email forwarding of wildcard addresses, allowing incoming emails without
having to register with an email provider or managing an exchange server.

But the main reason for registering early is to get an SSL certificate. My ISP likes to block incoming traffic on port
80 from time to time, making it impossible to get/renew certificates using Certbot with the HTTP challenge.

### 3. Get a temporary LetsEncrypt certificate on the domain

An easy way to get started is to manually get an initial certificate:

```
certbot certonly --preferred-challenges dns --manual -d dorn.haus
```

Then manually add & remove the TXT record in the Cloudflare UI.

I then set up a simple Nginx reverse-proxy and NAT port 443. This will be needed to serve the OpenID challenge via
Keycloak (next step).

### 4. Start a temporary Keycloak server

Fire up a Keycloak development server using Podman to create an initial user, `attila@dorn.haus`. I do this at home
while NAT'ing myself to the outside world, as well as making sure my LetsEncrypt cert is still functional.

```
export PASSWORD="$(pwgen -1sy 12)"
echo "admin password: $PASSWORD (temporary)"
podman run \
  --name keycloak \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 9000:9000 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD="$PASSWORD" \
  -e PROXY_ADDRESS_FORWARDING=true \
  -v /path/to/certs:/etc/certs \
  quay.io/keycloak/keycloak start \
  --proxy-headers forwarded \
  --hostname=https://dorn.haus/keycloak/ \
  --https-certificate-file=/etc/certs/cert.pem \
  --https-certificate-key-file=/etc/certs/privkey.pem \
  --log-level=INFO \
  --verbose
```

Next, configure WebFinger in Nginx (see `bootstrap/nginx.conf`). Create a new Keycloak realm, add a user (e.g.
`attila@dorn.haus`), and add the Tailscale client. The Tailscale Client ID & secret will be needed when connecting.

Once connected, we can sign in to Tailscale using Keycloak as the OIDC provider, and create a personal tailnet for our
domain, for free.

## 6️⃣ IPv6 networking

Currently the machines in the cluster are connected to the router that my ISP provides, through cheap 1 Gbps switches
that only do L2 forwarding. This router advertises two IPv6 prefixes:

- A `scope global`, `dynamic` prefix that belongs to the `2000::/3` range.
- A `scope global` static prefix in the `fd00::/8` range. This appears to be the prefix `fdaa:bbcc:ddee:0/64` on these
modems.

The router has IPv6 pinholing configured to access the load balancers from the outside. Cloudflare sits in front of
them and provides IPv4 connectivity.

For now, most networks run in dual-stack mode, all networks being part of the `10./8` & `fd10::/8` subnets, which are
both routable locally.

## 🧑‍💻️ Dev/Ops

The easiest way to get the required dependencies is to have `nix` and `direnv` configured. Entering the repo will
execute the `.envrc` file, which in turn will activate devenv to build the required dependencies.

Without `direnv`, one would need to manually run `devenv shell` to enter the development shell.

## 💡 Inspiration

Much of this was inspired by a number of similar repos:

- [Euvaz/GitOps-Home]
- [toboshii/home-ops]
- [onedr0p/home-ops]

[Euvaz/GitOps-Home]: https://github.com/Euvaz/GitOps-Home
[toboshii/home-ops]: https://github.com/toboshii/home-ops
[onedr0p/home-ops]: https://github.com/onedr0p/home-ops

## 🚧 Under Construction

There is an existing repository where I already have most of these configs, however it contains various secrets that
are not properly extracted out. This is an attempt to migrate exsting configs and redact any secrets.
