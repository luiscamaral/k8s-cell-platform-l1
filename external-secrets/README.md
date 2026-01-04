# External Secrets Operator

Manages external secrets from HashiCorp Vault.

## Prerequisites

1. HashiCorp Vault running at `http://vault.d.lcamaral.com`
2. Vault token with read access to `secret/` path

## Setup

### 1. Create Vault Policy

```bash
vault policy write kubernetes-secrets - <<EOF
path "secret/data/kubernetes/*" {
  capabilities = ["read", "list"]
}
EOF
```

### 2. Create Vault Token

```bash
vault token create -policy=kubernetes-secrets -ttl=8760h
```

### 3. Create Token Secret

```bash
# Copy example and fill in token
cp vault-token-secret.yaml.example vault-token-secret.yaml
# Edit with your token
kubectl apply -f vault-token-secret.yaml
```

### 4. Deploy ESO

```bash
make deploy-external-secrets
```

## Usage

Create ExternalSecret resources to sync secrets from Vault:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-secret
  data:
    - secretKey: password
      remoteRef:
        key: secret/data/kubernetes/my-app
        property: password
```

## Vault Paths

| Secret | Vault Path | Keys |
|--------|------------|------|
| Karpenter Proxmox | `secret/kubernetes/karpenter/proxmox-credentials` | token_id, token_secret, api_url |
| Karpenter Talos | `secret/kubernetes/karpenter/talos-values` | machineToken, machineCA, clusterID, clusterSecret, bootstrapToken, clusterEndpoint, clusterName, talosVersion, kubeletVersion |
| MinIO Root | `secret/kubernetes/minio/root-credentials` | rootUser, rootPassword |

## Vault Setup Commands

```bash
# Create policy for Kubernetes secrets
vault policy write kubernetes-secrets - <<EOF
path "secret/data/kubernetes/*" {
  capabilities = ["read", "list"]
}
EOF

# Create token with policy
vault token create -policy=kubernetes-secrets -ttl=8760h

# Store Karpenter Proxmox credentials
vault kv put secret/kubernetes/karpenter/proxmox-credentials \
  token_id="kubernetes@pve!karpenter" \
  token_secret="<proxmox-token>" \
  api_url="https://proxmox.home.lcamaral.com:8006/api2/json"

# Store Karpenter Talos values (get from terraform output)
vault kv put secret/kubernetes/karpenter/talos-values \
  machineToken="<machine-token>" \
  machineCA="<machine-ca-cert>" \
  clusterID="<cluster-id>" \
  clusterSecret="<cluster-secret>" \
  bootstrapToken="<bootstrap-token>" \
  clusterEndpoint="https://192.168.100.51:6443" \
  clusterName="k8s-lab" \
  talosVersion="1.12.0" \
  kubeletVersion="v1.34.0"
```
