# The Locker

> AKA Attila's homelab, running on commodity hardware in a locker (yes, an actual locker).

![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/attilaolah/homelab?labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)

## 📖 Overview

This repository contains Infrastructure as Code (IaC) and GitOps config files for managing my hobby cluster in the
basement. Inspired by popular repos like [toboshii/home-ops], it started out as a hybrid Talos/Alpine Kubernetes
cluster, but then got converted to Clan to better utilise the machines with wildly different specs.

- **🛠️ Unconventional hardware:** As much as I enjoy automating the software infrastructure, I also really like
  building custom hardware to power it all. I spend maybe half the time in front of the ⌨️ keyboard and half the time
  using 🪚🪛 power tools.
- **🌳 Low footprint:** All of the nodes are either old machines I am no longer using, or used machines I bought for
  next to nothing. Many use passive cooling and have no moving parts at all.

## Talos/Alpine + Kubernetes → NixOS + Systemd

The cluster started out with Talos nodes, managed by Flux. Back in the early days, all software was running inside
containers, managed by Kubernetes.

Then, over time, I got more and more machines that were too low-spec to even start the Talos kernel. Even some of the
ones that did start had less than 4G disk space, which is the minimum recommended by Talos. To work around that, I
installed Alpine on the low-end machines, running nothing but K0s, so those too could join the cluster as worker nodes.

That did function, however as the cluster grew, it became obvious that the containerisation overhead was eating up
almost all of the capacity. After running the standard tools (Cilium, Node Exporter, log collection, kubelet itself)
the nodes were essentially busy doing nothing. This was a shame since these tiny machines, while not suitable for
running heavier workloads, would be excellent to host some of the tiny appliances like Caddy, etcd and could increase
the redundancy of the cluster by providing additional jumphosts or extra nodes for quorum.

As a result, I re-built the cluster from scratch, using Clan. There is no containerisation overhead, all binaries are
installed into the host's Nix store and compiled against the shared libraries, resulting in much lower disk footprint,
but also lower CPU and memory footprint since there is no container overhead.

Process isolation is provided by Systemd using standard namespaces. Bubblewrap is used for additional protection
against less-trusted code. Podman can still provide a container wrapper if necessary.

High availability is achieved by tools such as Keepalived. This is a lot more manual and quite rudimentary compared to
full Kubernetes scheduling. In practice however, the cluster shape was so asymmetric that most workloads had to be
pinned to a few nodes as candidates anyway. In the end it is uptime that matters.

## 🚧 IPv6 networking

Currently, the cluster machines are connected to my ISP‑provided router via inexpensive 1 Gbps, L2‑only switches. This
router only advertises a global unicast prefix, no ULA (unique local address). The prefix belongs to the `2000::/3`
range.

The router has IPv6 pinholing configured to access the load balancers from the outside. Cloudflare sits in front of the
load balancers and provides IPv4 connectivity.

For now, most nodes are configured to run in dual-stack mode, using `192.168.1.0/24` and the advertised IPv6 GUA
subnet, as well as the automatic link-local `fe80::/10` subnet.

## 🧑‍💻️ Dev/Ops

The easiest way to get the required dependencies is to have `nix` and `direnv` configured. Entering the repo will
execute the `.envrc` file, which in turn will activate devenv to build the required dependencies.

Without `direnv`, one would need to manually run `nix flake develop` to enter the development shell.

Operational docs:

- [PKI onboarding](docs/pki.md)

## 💡 Inspiration

Much of this was inspired by a number of similar repos:

- [toboshii/home-ops]
- [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
- [Euvaz/GitOps-Home](https://github.com/Euvaz/GitOps-Home)

[toboshii/home-ops]: https://github.com/toboshii/home-ops
