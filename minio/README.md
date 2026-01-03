# MinIO S3-Compatible Object Storage

High-performance, S3-compatible object storage for the Kubernetes Cell Platform.

## Components

- **MinIO Server**: S3-compatible object storage
- **MinIO Console**: Web-based management UI
- **Pre-configured Buckets**: For Harbor, Velero, Loki, Tempo

## Prerequisites

1. **cert-manager** deployed with internal CA
2. **NFS Provisioner** deployed (for PVC storage)
3. **Ingress Controller** (nginx-ingress)

## Installation

```bash
# Deploy via Makefile
make deploy-minio

# Or manually:
helm repo add minio https://charts.min.io/
helm repo update

kubectl apply -k .

helm install minio minio/minio \
  --namespace minio \
  --values helm/minio-values.yaml
```

## Access

| Endpoint | URL |
|----------|-----|
| S3 API | https://minio.lab.home |
| Console | https://minio-console.lab.home |

### Default Credentials

```yaml
User: admin
Password: minio-secret-key-change-me
```

**IMPORTANT**: Change the default credentials before production use!

## Pre-configured Buckets

| Bucket | Purpose | Consumer |
|--------|---------|----------|
| `harbor-registry` | Container image storage | Harbor (L3) |
| `velero-backups` | Cluster backup storage | Velero (L5) |
| `loki-chunks` | Log data chunks | Loki (L4) |
| `tempo-traces` | Distributed traces | Tempo (L4) |

## Configuration

### Update Credentials

1. Create a secret:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: minio
type: Opaque
stringData:
  rootUser: admin
  rootPassword: your-secure-password
```

2. Update helm values:
```yaml
existingSecret: minio-credentials
```

### S3 Client Configuration

For applications connecting to MinIO:

```yaml
s3:
  endpoint: minio.minio.svc.cluster.local:9000
  # Or external: minio.lab.home
  region: us-east-1
  accessKey: <from-secret>
  secretKey: <from-secret>
  secure: true  # Use HTTPS
```

### mc CLI Configuration

```bash
# Install mc
brew install minio/stable/mc

# Configure alias
mc alias set homelab https://minio.lab.home admin minio-secret-key-change-me

# List buckets
mc ls homelab

# Create bucket
mc mb homelab/my-bucket
```

## Usage Examples

### Harbor Integration

```yaml
# harbor-values.yaml
storage:
  s3:
    accesskey: harbor-access-key
    secretkey: harbor-secret-key
    bucket: harbor-registry
    region: us-east-1
    regionendpoint: http://minio.minio.svc.cluster.local:9000
    secure: false  # Internal traffic
```

### Velero Integration

```yaml
# velero configuration
configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: velero-backups
      config:
        region: us-east-1
        s3Url: http://minio.minio.svc.cluster.local:9000
        s3ForcePathStyle: true
```

### Loki Integration

```yaml
# loki-values.yaml
storage:
  type: s3
  s3:
    endpoint: minio.minio.svc.cluster.local:9000
    bucketnames: loki-chunks
    region: us-east-1
    access_key_id: loki-access-key
    secret_access_key: loki-secret-key
    insecure: true  # Internal traffic
    s3forcepathstyle: true
```

## Distributed Mode

For production with multiple nodes, change to distributed mode:

```yaml
# helm values
mode: distributed

replicas: 4

persistence:
  size: 100Gi

resources:
  requests:
    memory: 1Gi
    cpu: 500m
```

## Troubleshooting

### Check Status

```bash
# Pod status
kubectl get pods -n minio

# Logs
kubectl logs -n minio -l app=minio

# Check PVC
kubectl get pvc -n minio
```

### Common Issues

**PVC Pending**:
```bash
# Check StorageClass
kubectl get storageclass

# Check NFS provisioner
kubectl get pods -n nfs-provisioner
```

**Certificate Issues**:
```bash
# Check certificate
kubectl get certificate -n minio
kubectl describe certificate minio-tls -n minio
```

**Access Denied**:
```bash
# Verify credentials
kubectl get secret -n minio minio -o jsonpath='{.data.rootUser}' | base64 -d
```

## Security Considerations

1. **Change default credentials** before production
2. **Use TLS** for all external access (enabled by default)
3. **Create service accounts** with minimal permissions per application
4. **Enable audit logging** for compliance
5. **Backup bucket policies** regularly
