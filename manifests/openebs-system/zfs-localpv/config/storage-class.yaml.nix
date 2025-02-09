{k, ...}:
k.api "StorageClass.storage.k8s.io" {
  metadata.name = "openebs-zfspv";
  parameters = {
    recordsize = "128k";
    encryption = "on";
    compression = "off";
    dedup = "off";
    fstype = "zfs";
    poolname = "zfspv";
  };
  provisioner = "zfs.csi.openebs.io";
  reclaimPolicy = "Retain";
}
