# L1 Cluster Platform

Core platform services for the Kubernetes Cell Platform.

## Overview

L1 provides essential cluster services that enable application workloads:

| Service | Purpose | Namespace |
|---------|---------|-----------|
| **MetalLB** | LoadBalancer for bare-metal | metallb-system |
| **external-dns** | Automatic DNS record management | external-dns |
| **Karpenter** | Node autoscaling | kube-system |
| **Test Service** | Deployment validation | test-service |

## Architecture

```
L0 Infrastructure (Terraform + Talos)
    ↓
L1 Cluster Platform (This directory)
    ├── MetalLB (LoadBalancer IPs)
    ├── external-dns (DNS → Pi-hole)
    ├── Karpenter (Node autoscaling)
    └── Test service (Validation)
    ↓
L2 Core Platform (GitOps, Policy, Mesh)
    ↓
L3 Applications (Your workloads)
```

## Quick Start

```bash
# Deploy all L1 services
make deploy-all

# Check status
make status

# Verify deployment
make verify
```

## Prerequisites

1. **L0 Infrastructure deployed** - Talos cluster running
2. **Kubeconfig configured** - `kubectl get nodes` works
3. **Cilium CNI operational** - All nodes Ready

## Deployment

### Option 1: All Services at Once

```bash
make deploy-all
```

### Option 2: Individual Services

```bash
make deploy-metallb       # LoadBalancer
make deploy-external-dns  # DNS automation
make deploy-test-service  # Validation
make deploy-karpenter     # Node autoscaling (optional)
```

### Option 3: Manual kubectl

```bash
kubectl apply -k metallb/
kubectl apply -k external-dns/
kubectl apply -f test-service/whoami.yaml
```

## Configuration

### MetalLB IP Pool

Edit `metallb/ipaddresspool.yaml`:
```yaml
addresses:
  - 192.168.100.220-192.168.100.240
```

### external-dns (Pi-hole)

Edit `external-dns/secret.yaml` and `external-dns/deployment.yaml`:
- Pi-hole server: `http://192.168.100.254`
- Domain: `lab.home`

### Karpenter

See [karpenter/README.md](karpenter/README.md) for:
- Proxmox API token setup
- VM template creation
- Secret configuration

## Verification

```bash
# Check all services
make status

# Verify deployment
make verify

# Test LoadBalancer + DNS
curl http://whoami.lab.home
```

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make deploy-all` | Deploy all L1 services |
| `make deploy-metallb` | Deploy MetalLB |
| `make deploy-external-dns` | Deploy external-dns |
| `make deploy-karpenter` | Deploy Karpenter |
| `make deploy-test-service` | Deploy test service |
| `make status` | Check all services |
| `make verify` | Verify deployment |
| `make karpenter-status` | Karpenter status |
| `make karpenter-logs` | Karpenter logs |
| `make karpenter-test` | Test autoscaling |
| `make karpenter-uninstall` | Remove Karpenter |
| `make clean` | Remove test resources |

## Directory Structure

```
l1_cluster_platform/
├── metallb/              # LoadBalancer
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
│   ├── secret-*.yaml
│   ├── proxmox-*.yaml
│   ├── nodepool-*.yaml
│   ├── helm/
│   └── test/
│
├── test-service/        # Validation
│   └── whoami.yaml
│
├── Makefile            # Operations
├── README.md           # This file
└── CLAUDE.md          # AI context
```

## Troubleshooting

### MetalLB Not Assigning IPs

```bash
kubectl get ipaddresspool -n metallb-system
kubectl describe svc <service-name>
kubectl logs -n metallb-system -l component=controller
```

### DNS Records Not Created

```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
# Check: Pi-hole URL, password, network connectivity
```

### Karpenter Not Scaling

```bash
kubectl get nodeclaims
kubectl describe nodeclaim <name>
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter-proxmox
```

## Cleanup

```bash
# Remove test resources
make clean

# Remove all L1 services
kubectl delete -k metallb/
kubectl delete -k external-dns/
make karpenter-uninstall
```

## Related

- **L0 Infrastructure**: Terraform + Talos provisioning
- **L2 Core Platform**: GitOps, Policy, Service Mesh

## Resources

- [MetalLB Documentation](https://metallb.universe.tf/)
- [external-dns Documentation](https://kubernetes-sigs.github.io/external-dns/)
- [Karpenter for Proxmox](https://github.com/sergelogvinov/karpenter-provider-proxmox)

---

**Layer**: L1 Cluster Platform
**Status**: Ready for deployment
**Prerequisites**: L0 operational