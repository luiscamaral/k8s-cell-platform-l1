# Karpenter for Proxmox

Automatic node autoscaling for Kubernetes on Proxmox VE using [karpenter-provider-proxmox](https://github.com/sergelogvinov/karpenter-provider-proxmox).

## Overview

Karpenter provides just-in-time node provisioning, automatically creating and terminating VMs based on workload demands.

### Hybrid Worker Strategy

| Worker Type | Management | Purpose | Count |
|------------|------------|---------|-------|
| **Static** | Terraform | Baseline, always-on | 3 (existing) |
| **Dynamic** | Karpenter | Burst, scale-to-zero | 0-10 |

## Prerequisites

### 1. Proxmox API Token

Create a dedicated Karpenter role and API token on Proxmox:

```bash
# On Proxmox host
pveum role add Karpenter -privs "Datastore.Allocate Datastore.AllocateSpace \
  Datastore.AllocateTemplate Datastore.Audit VM.Audit VM.Allocate VM.Clone \
  VM.Config.CDROM VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network \
  VM.Config.HWType VM.Config.Cloudinit VM.Config.Options VM.PowerMgmt \
  SDN.Audit SDN.Use Sys.Audit Sys.AccessNetwork Mapping.Audit Mapping.Use"

pveum user add kubernetes@pve
pveum aclmod / -user kubernetes@pve -role Karpenter
pveum user token add kubernetes@pve karpenter -privsep 0
# Save the token_id and token_secret!
```

### 2. VM Template

Create a Talos worker VM template in Proxmox:

```bash
# Option A: From existing worker
qm template <worker-vmid>

# Option B: Manual creation
qm create 9000 --name talos-worker-template \
  --memory 1024 --cores 1 --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single --agent enabled=1
qm importdisk 9000 talos-1.11.5-metal-amd64.qcow2 local-lvm
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0
qm template 9000
```

### 3. Configure Secrets in Vault

Karpenter secrets are managed via External Secrets Operator (ESO) pulling from HashiCorp Vault.

#### Store Proxmox Credentials in Vault

```bash
vault kv put secret/kubernetes/karpenter/proxmox-credentials \
  token_id="kubernetes@pve!karpenter" \
  token_secret="<your-proxmox-api-token>" \
  api_url="https://proxmox.home.lcamaral.com:8006/api2/json"
```

#### Store Talos Values in Vault

Extract values from Terraform state:

```bash
# Get values from Terraform output
cd l0_infrastructure/terraform/providers/proxmox
terraform output -json

# Store in Vault
vault kv put secret/kubernetes/karpenter/talos-values \
  machineToken="<from terraform output>" \
  machineCA="<machine CA cert PEM>" \
  clusterID="<cluster ID>" \
  clusterSecret="<cluster secret>" \
  bootstrapToken="<bootstrap token>" \
  clusterEndpoint="https://192.168.100.51:6443" \
  clusterName="k8s-lab" \
  talosVersion="1.12.0" \
  kubeletVersion="v1.34.0"
```

#### Alternative: Manual Secrets (Development Only)

For development without Vault, copy the example files:

```bash
cp secret-proxmox-credentials.yaml.example secret-proxmox-credentials.yaml
cp secret-talos-values.yaml.example secret-talos-values.yaml
# Edit with your values
kubectl apply -f secret-proxmox-credentials.yaml
kubectl apply -f secret-talos-values.yaml
```

## Quick Start

```bash
# Deploy Karpenter (from parent directory)
make karpenter-deploy

# Check status
make karpenter-status

# Test scaling
make karpenter-test

# View logs
make karpenter-logs
```

## Directory Structure

```
karpenter/
├── kustomization.yaml                      # Kustomize configuration
├── externalsecret-proxmox-credentials.yaml # ESO: Proxmox API credentials from Vault
├── externalsecret-talos-values.yaml        # ESO: Talos secrets from Vault
├── secret-talos-template.yaml              # Talos machine config Go template
├── secret-proxmox-credentials.yaml.example # Example for manual setup
├── secret-talos-values.yaml.example        # Example for manual setup
├── proxmox-unmanaged-template.yaml         # VM template reference
├── proxmox-nodeclass.yaml                  # Node class configuration
├── nodepool-burst.yaml                     # NodePool for burst capacity
├── helm/
│   └── karpenter-proxmox-values.yaml       # Helm values
├── test/
│   └── test-deployment.yaml                # Test workload
└── README.md                               # This file
```

## Configuration

### NodePool Limits

Edit `nodepool-burst.yaml` to adjust limits:

```yaml
spec:
  limits:
    cpu: "64"       # Max 64 vCPUs
    memory: 256Gi   # Max 256GB
```

### Instance Types

Available instance families (CPU:Memory ratio):

| Family | Ratio | Examples |
|--------|-------|----------|
| c1 | 1:2 | c1.4VCPU-8GB |
| s1 | 1:4 | s1.4VCPU-16GB, s1.8VCPU-32GB |
| m1 | 1:8 | m1.4VCPU-32GB, m1.8VCPU-64GB |

### Workload Targeting

```yaml
# Target static workers only
nodeSelector:
  node-type: static

# Target Karpenter nodes only
nodeSelector:
  node-type: karpenter

# Allow either (default)
# No nodeSelector needed
```

## Validation

```bash
# Check controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter-proxmox

# Check resources
kubectl get ProxmoxNodeClass,NodePool,NodeClaim

# Watch scaling
kubectl get nodeclaims -w
```

## Troubleshooting

### Controller Not Starting

```bash
# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter-proxmox

# Verify secrets
kubectl get secrets -n kube-system | grep karpenter
```

### Nodes Not Provisioning

```bash
# Check NodeClaim status
kubectl describe nodeclaim <name>

# Verify template exists in Proxmox
qm list | grep template

# Check Proxmox API connectivity
curl -k https://proxmox.home.lcamaral.com:8006/api2/json
```

### Talos Boot Issues

```bash
# Check VM console in Proxmox
qm terminal <vmid>

# Verify Talos config is delivered via CDROM
# Check machine config in Proxmox VM details
```

## Uninstall

```bash
make karpenter-uninstall
```

This will:
1. Delete all NodeClaims (terminate VMs)
2. Remove NodePool and NodeClass
3. Uninstall Helm release
4. Delete secrets

## Resources

- [karpenter-provider-proxmox](https://github.com/sergelogvinov/karpenter-provider-proxmox)
- [Karpenter Documentation](https://karpenter.sh/docs/)
- [Talos Linux](https://www.talos.dev/)
- [Proxmox VE](https://www.proxmox.com/en/proxmox-ve)