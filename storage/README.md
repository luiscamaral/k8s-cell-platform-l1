# NFS Storage Provisioner

Dynamic PersistentVolume provisioning using NFS.

## Components

- **nfs-subdir-external-provisioner**: Dynamic PV provisioner
- **nfs-client StorageClass**: Default storage class for PVCs

## Prerequisites

1. NFS server accessible from all cluster nodes
2. NFS export configured with proper permissions
3. Helm 3.x installed

### NFS Server Setup (Synology Example)

```bash
# On Synology NAS:
# 1. Control Panel > Shared Folder > Create
#    - Name: k8s-storage
#    - Location: Volume 1

# 2. Control Panel > File Services > NFS > Enable
#    - NFSv4.1 support: Enabled

# 3. Shared Folder > Edit > NFS Permissions
#    - Hostname: 192.168.100.0/24
#    - Privilege: Read/Write
#    - Squash: Map all users to admin
#    - Security: sys
#    - Enable async: Yes
```

## Installation

```bash
# Add Helm repo
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo update

# Create namespace
kubectl apply -k .

# Install NFS provisioner
helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --values helm/nfs-provisioner-values.yaml
```

## Verify Installation

```bash
# Check pods
kubectl get pods -n nfs-provisioner

# Check StorageClass
kubectl get storageclass

# Test PVC creation
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-nfs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 1Gi
EOF

# Verify PVC is bound
kubectl get pvc test-nfs-claim

# Clean up test
kubectl delete pvc test-nfs-claim
```

## Configuration

### Cell-Specific Values

Update `helm/nfs-provisioner-values.yaml` with values from `meta/cell-config.yaml`:

| Setting | Cell Config Path | Default |
|---------|------------------|---------|
| NFS Server | `storage.nfs.server` | 192.168.100.254 |
| NFS Path | `storage.nfs.path` | /volume1/k8s-storage |
| StorageClass | `storage.class` | nfs-client |

### StorageClass Options

```yaml
# Retain volumes on delete (for production)
storageClass:
  reclaimPolicy: Retain

# Immediate binding (default)
storageClass:
  volumeBindingMode: Immediate

# Wait for first consumer (for topology-aware)
storageClass:
  volumeBindingMode: WaitForFirstConsumer
```

## Usage

### Create a PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  accessModes:
    - ReadWriteMany    # NFS supports RWX
  storageClassName: nfs-client
  resources:
    requests:
      storage: 10Gi
```

### Use in Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: my-app-data
```

## Directory Structure on NFS

PVCs create subdirectories with naming pattern:
```
/volume1/k8s-storage/
├── namespace-pvcname-pv-randomid/
│   └── <application data>
├── archived-namespace-pvcname-pv-randomid/  # Deleted PVCs (if archiveOnDelete: true)
```

## Troubleshooting

### PVC Stuck in Pending

```bash
# Check provisioner logs
kubectl logs -n nfs-provisioner -l app=nfs-subdir-external-provisioner

# Check events
kubectl describe pvc <pvc-name>
```

### Mount Failures

```bash
# Test NFS connectivity from a node
showmount -e 192.168.100.254

# Check pod events
kubectl describe pod <pod-name>
```

### Permission Issues

Ensure NFS export has correct permissions:
- Squash: Map all users to admin
- UID/GID mapping matches container users

## Alternatives

| Provisioner | Use Case |
|-------------|----------|
| **NFS Subdir** | Simple, external NFS server |
| **Longhorn** | Distributed storage, HA, built-in UI |
| **OpenEBS Mayastor** | High-performance, NVMe-oF |
| **local-path** | Single-node, no external storage |
