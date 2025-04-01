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
