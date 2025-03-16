## Talos

Talos can be bootstrapped more or less using `talos:bootstrap`.

## Flux + Secrets

Prerequisites:

- API server (KAS), controller-manager and scheduler should all be running.
- Cilium should be installed and running (even if `cilium status` shows errors due to TLS problems initially).

The Flux operator and instance can be installed with `task flux:install`, but it needs the following to get started:

- A GHCR secret to download the artifact, this can be created using:

```sh
kubectl --namespace=flux-system create secret docker-registry oci-auth \
  --docker-username=attilaolah --docker-password=$GHCR_TOKEN --docker-server=ghcr.io
```

All secrets, including this one, is managed by the external-secrets operator (ESO), except for the GCP service account
key used by ESO itself. The key is not stored anywhere else and cannot be retrievedfrom GCP, a new one must be created
for service account number `113717540367402514039`, named `external-secrets`.

This secret should be created manually using the JSON key downloaded from GCP using the command below:

```sh
kubectl --namespace=kube-system create secret generic gcp-secrets-service-account \
  --from-file=key=dornhaus-keyid.js
```

Finally, for Flux to be able to bootstrap, it needs the external secrets CRD. The easiest way to get that is to instal
ESO using the official Helm chart, like so:

```sh
helm repo add external-secrets https://charts.external-secrets.io
helm --namespace=kube-system install external-secrets external-secrets/external-secrets \
  --set=installCRDs=true
```

## ZFS

For now, I just create the ZFS pools manually from within a privileged Alpine container, using `nsenter` to enter the
host init namespace from the pod:

```sh
nsenter --target 1 --mount --ipc --net --pid chroot /host \
  zpool create -f -o ashift=12 -m /var/zfs/tank tank /dev/sdb
```

The `ashift=12` above is for HDDs with 4K sectors. To verify:

```sh
nsenter --target 1 --mount --ipc --net --pid chroot /host \
  zpool list
```
