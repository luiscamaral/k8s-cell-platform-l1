# CLAUDE.md - L1 Cluster Platform Context

This file provides guidance to Claude Code when working with the L1 Cluster Platform layer.

## Layer Overview

**Layer**: L1 - Cluster Platform
**Purpose**: Core platform services that enable application workloads
**Dependencies**: L0 Infrastructure must be deployed first
**Consumers**: L2 Core Platform, L3 Applications

## Components

| Service | Purpose | Namespace | Status |
|---------|---------|-----------|--------|
| **MetalLB** | LoadBalancer for bare-metal | metallb-system | ✅ Deployed |
| **nginx-ingress** | HTTP/HTTPS ingress controller | ingress-nginx | ✅ Deployed |
| **metrics-server** | Metrics API for HPA/VPA | kube-system | ✅ Deployed |
| **external-dns** | Automatic DNS record management | external-dns | ✅ Deployed |
| **Linkerd** | Service mesh, mTLS | linkerd | ✅ Deployed |
| **Linkerd-viz** | Mesh dashboard/observability | linkerd-viz | ✅ Deployed |
| **Karpenter** | Node autoscaling | kube-system | ✅ Deployed |
| **cert-manager** | TLS certificate automation | cert-manager | ✅ Deployed |
| **NFS Provisioner** | Dynamic PersistentVolume provisioning | nfs-provisioner | ✅ Deployed |
| **MinIO** | S3-compatible object storage | minio | ✅ Deployed |
| **External Secrets** | Vault secret synchronization | external-secrets | ⏳ Ready |
| **Test Service** | Deployment validation | test-service | ✅ Deployed |

> **Note**: L1 components are managed via Helm/Makefile (NOT ArgoCD)
> Linkerd is managed via `linkerd` CLI, not Helm

## Directory Structure

```
l1_cluster_platform/
├── metallb/              # LoadBalancer configuration
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── ipaddresspool.yaml
│   └── l2advertisement.yaml
│
├── external-dns/         # DNS automation
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   └── secret.yaml
│
├── karpenter/           # Node autoscaling
│   ├── kustomization.yaml
│   ├── secret-*.yaml    # Credentials
│   ├── proxmox-*.yaml   # Proxmox config
│   ├── nodepool-*.yaml  # NodePools
│   ├── helm/            # Helm values
│   └── test/            # Test workloads
│
├── cert-manager/        # TLS certificate management
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── ca/              # Internal CA bootstrap
│   ├── issuers/         # ClusterIssuers
│   └── helm/            # Helm values
│
├── storage/             # PersistentVolume provisioning
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── helm/            # NFS provisioner values
│
├── minio/               # S3-compatible storage
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── helm/            # MinIO values
│
├── external-secrets/    # Vault secret sync
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── cluster-secret-store.yaml  # Vault backend config
│   └── helm/            # ESO values
│
├── test-service/        # Validation
│   └── whoami.yaml
│
├── Makefile             # Deployment operations
├── README.md            # Documentation
└── CLAUDE.md           # This file
```

## Quick Commands

```bash
# Deploy all L1 services
make deploy-all

# Check status
make status

# Individual services
make deploy-metallb
make deploy-external-dns
make deploy-karpenter
make deploy-test-service

# Karpenter management
make karpenter-status
make karpenter-logs
make karpenter-test
make karpenter-uninstall
```

## Configuration

### MetalLB IP Pool
```yaml
# metallb/ipaddresspool.yaml
addresses:
  - 192.168.100.220-192.168.100.240
```

### External-DNS (Pi-hole)
```yaml
# external-dns/deployment.yaml
- --provider=pihole
- --pihole-server=http://192.168.100.254
```

### Karpenter Hybrid Strategy
- **Static workers (2)**: Terraform-managed baseline
- **Dynamic workers (0-10)**: Karpenter-managed burst
- **Scaling time**: ~55 seconds

## Dependencies

### Requires from L0
- Kubernetes cluster running
- Cilium CNI operational
- kubectl access configured
- Helm installed (for Karpenter)

### Provides to L2/L3
- LoadBalancer IP assignment
- DNS record automation
- Automatic node scaling
- Service discovery

## Deployment Order

1. **MetalLB** - Required for LoadBalancer services
2. **nginx-ingress** - HTTP/HTTPS ingress controller
3. **external-dns** - Requires MetalLB for its own service
4. **cert-manager** - TLS certificate automation with internal CA
5. **NFS Provisioner** - Dynamic PVC provisioning (reads config from cell-config.yaml)
6. **MinIO** - S3-compatible storage for Harbor, Velero, Loki, Tempo
7. **Karpenter** - Optional, requires additional setup
8. **Test Service** - Validates full stack

## Karpenter Prerequisites

Before deploying Karpenter:

1. **Proxmox API Token**
   ```bash
   pveum user token add kubernetes@pve karpenter -privsep 0
   ```

2. **VM Template** in Proxmox named `talos-worker-template`

3. **Update Secrets** with real values:
   - `karpenter/secret-proxmox-credentials.yaml`
   - `karpenter/secret-talos-values.yaml`

## Troubleshooting

### MetalLB Not Assigning IPs
```bash
kubectl get ipaddresspool -n metallb-system
kubectl describe svc <service-name>
kubectl logs -n metallb-system -l app.kubernetes.io/name=metallb
```

### external-dns Not Creating Records
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
# Check Pi-hole admin for new records
```

### Karpenter Not Scaling
```bash
kubectl get nodeclaims
kubectl describe nodeclaim <name>
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter-proxmox
```

## Integration Points

### With L0 Infrastructure
- Uses kubeconfig from L0
- Karpenter creates VMs on same Proxmox
- Same network configuration

### With L2 Core Platform
- L1 services are managed by Helm/Makefile (NOT ArgoCD)
- Kyverno policies can validate L1 resources
- Linkerd can mesh L1 services

## Best Practices

1. **Deploy MetalLB first** - Other services need LoadBalancer
2. **Test with whoami** - Validates full stack before production
3. **Start without Karpenter** - Add autoscaling after stable baseline
4. **Use Kustomize** - All services use kustomization.yaml
5. **Check logs** - Most issues visible in pod logs

## Version Information

| Component | Version | Chart/Image |
|-----------|---------|-------------|
| MetalLB | 0.15.3 | metallb/metallb (Helm) |
| nginx-ingress | 4.14.1 | ingress-nginx/ingress-nginx (Helm) |
| metrics-server | 3.13.0 | metrics-server/metrics-server (Helm) |
| external-dns | 0.17.0 | registry.k8s.io/external-dns (Kustomize) |
| Linkerd | edge-25.12.3 | linkerd CLI |
| Linkerd-viz | edge-25.12.3 | linkerd CLI |
| Karpenter | 0.4.1 | karpenter-provider-proxmox (Helm) |
| cert-manager | 1.16.2 | jetstack/cert-manager (Helm) |
| NFS Provisioner | 4.0.18 | nfs-subdir-external-provisioner (Helm) |
| MinIO | 5.4.0 | minio/minio (Helm) |
| External Secrets | 0.12.1 | external-secrets/external-secrets (Helm) |

## Related Layers

- **L0 Infrastructure**: `/Users/lamaral/Library/CloudStorage/.../l0_infrastructure/`
- **L2 Core Platform**: `/Users/lamaral/dev/kubernetes_cell_platform/l2_core_platform/`

---

**Layer**: L1 Cluster Platform
**Status**: ✅ Fully Deployed
**Last Updated**: 2026-01-03
**Prerequisites**: L0 operational