# csi-cloudscale

A commodore Component for csi-cloudscale

## Details

This component installs the [csi-cloudscale](https://github.com/cloudscale-ch/csi-cloudscale)
driver into the `kube-system` namespace.

## Encrypted PVs

To use encrypted PVs the provided StorageClasses `fast-encrypted` and `bulk-encrypted` can be used.
A secret in the same namespace as the PVC must exist and can be created as follows:

```
kubectl -n $MYNS create secret generic $MYPVCNAME-luks-key --from-literal=luksKey=$(pwgen 32 1)
```

This automatically creates LUKS encrypted volumes. On the node where the PV is mounted, the following
commands can be used to check for these volumes:

```
dmsetup ls --target crypt
lsblk --fs
cryptsetup -v status
```

Example:
```
root@synfra3:~# cryptsetup -v status pvc-2c062ec1-3b9e-499c-915f-6810d646ea82
/dev/mapper/pvc-2c062ec1-3b9e-499c-915f-6810d646ea82 is active and is in use.
  type:    LUKS1
  cipher:  aes-xts-plain64
  keysize: 512 bits
  key location: dm-crypt
  device:  /dev/vdb
  sector size:  512
  offset:  4096 sectors
  size:    10481664 sectors
  mode:    read/write
Command successful.
```