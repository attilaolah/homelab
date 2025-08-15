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

For bootstrapping with a custom domain, see: [“Custom Domain (one-time)”](bootstrap/README.md#custom-domain-one-time).

## 🚧 IPv6 networking

Currently, the cluster machines are connected to my ISP‑provided router via inexpensive 1 Gbps, L2‑only switches. This
router advertises two IPv6 prefixes:

- A `scope global`, `dynamic` prefix that belongs to the `2000::/3` range.
- A Unique Local Address (ULA) prefix in `fd00::/8` (often shown as `scope global` in `ip addr`). On these modems this
  appears as `fdaa:bbcc:ddee:0/64`.

The router has IPv6 pinholing configured to access the load balancers from the outside. Cloudflare sits in front of the
load balancers and provides IPv4 connectivity.

For now, most networks run in dual-stack mode, with all networks in the `10.0.0.0/8` and `fd10::/8` subnets, both
routable locally.

## 🧑‍💻️ Dev/Ops

The easiest way to get the required dependencies is to have `nix` and `direnv` configured. Entering the repo will
execute the `.envrc` file, which in turn will activate devenv to build the required dependencies.

Without `direnv`, one would need to manually run `devenv shell` to enter the development shell.

## 💡 Inspiration

Much of this was inspired by a number of similar repos:

- [toboshii/home-ops]
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
- [Euvaz/GitOps-Home](https://github.com/Euvaz/GitOps-Home)

[toboshii/home-ops]: https://github.com/toboshii/home-ops
