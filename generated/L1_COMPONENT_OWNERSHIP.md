# L1 Platform Component Ownership

**Generated**: 2025-12-30
**Purpose**: Documents L1 layer component responsibilities and boundaries

---

## Layer Architecture

```
L0 (Infrastructure)     - Terraform/Proxmox
    ↓ Provisions
Talos Cluster           - Machine config, kubelet, containerd
    ↓ Inline manifests
L1 (Cluster Platform)   - CNI, Load Balancing, DNS automation
    ↓ Deployed via kubectl/GitOps
L2 (Core Platform)      - GitOps, Policy, Service Mesh, Secrets
    ↓ Applications
L3+ (Applications)      - Workloads
```

---

## L1 Managed Components

These components are infrastructure-level and must be managed at L1, NOT via L2 GitOps (Argo CD/Helm).

### 1. Cilium CNI

| Attribute | Value |
|-----------|-------|
| **Current Version** | v1.16.4 |
| **Managed By** | Talos inline manifests |
| **Upgrade Method** | Talos machine config update |
| **Why L1** | CNI is required before cluster networking works; Talos security model requires elevated privileges |

**Important**: Do NOT install Cilium via Helm on Talos. The Helm chart requires capabilities (`SYS_ADMIN`, `SYS_MODULE`) that Talos blocks for security. Cilium must be deployed via Talos inline manifests.

**Upgrade Process**:
```bash
# 1. Update Talos machine config with new Cilium version
# 2. Apply to control plane nodes first
talosctl apply-config --nodes <cp-nodes> -f controlplane.yaml

# 3. Apply to worker nodes
talosctl apply-config --nodes <worker-nodes> -f worker.yaml

# 4. Verify
kubectl get pods -n kube-system -l k8s-app=cilium
```

### 2. MetalLB (Load Balancer)

| Attribute | Value |
|-----------|-------|
| **Current Version** | v0.14.9 → v0.15.3 (L2 upgraded) |
| **Managed By** | kubectl apply -k / Argo CD |
| **IP Pool** | 192.168.100.200-250 |
| **Mode** | Layer 2 |
| **Why L1** | Required for LoadBalancer services before L2 components can be exposed |

**Location**: `l1_platform/metallb/`

### 3. External-DNS

| Attribute | Value |
|-----------|-------|
| **Current Version** | v0.17.0 |
| **Managed By** | kubectl apply -k |
| **Provider** | Pi-hole |
| **Domain** | lab.home |
| **Why L1** | DNS automation is infrastructure-level; required before L2 services need DNS |

**Location**: `l1_platform/external-dns/`

---

## L2 Components (Reference)

These are managed at L2 via Argo CD GitOps:

| Component | Version | Purpose |
|-----------|---------|---------|
| Argo CD | v3.2.3 | GitOps control plane |
| Kyverno | v1.16.1 | Policy engine |
| Linkerd | edge-25.12.3 | Service mesh |
| Linkerd Viz | edge-25.12.3 | Observability |
| Metrics Server | v0.8.0 | HPA metrics |
| SOPS + age | 3.11.0 | Secret encryption |

**Location**: `l2_core-platform/`

---

## Dependency Graph

```
Talos Cluster (L0)
    │
    ├── Cilium CNI (L1/Talos)
    │       └── All pod networking depends on this
    │
    ├── MetalLB (L1)
    │       └── LoadBalancer services
    │           └── Argo CD UI, Linkerd Viz, etc.
    │
    └── External-DNS (L1)
            └── DNS records for services
                └── argocd.lab.home, linkerd.lab.home, etc.
```

---

## Upgrade Coordination

When upgrading L1 components:

1. **Cilium**: Requires Talos machine config update. Schedule maintenance window.
2. **MetalLB**: Can be upgraded via Argo CD, but verify IP pool continuity.
3. **External-DNS**: Can be upgraded via kubectl/Argo CD.

**Cross-layer impact**:
- Cilium upgrade may cause brief network disruption
- MetalLB upgrade preserves IP assignments if pool unchanged
- External-DNS upgrade is typically transparent

---

## Known Issues

### Cilium Helm Install on Talos (DO NOT USE)

A Helm install of Cilium was attempted on 2025-12-28 and failed with:
```
unable to apply caps: can't apply capabilities: operation not permitted
```

**Resolution**: The failed Helm release should be removed:
```bash
helm uninstall cilium -n kube-system
```

The original Talos-managed Cilium continues to provide CNI functionality.

---

## Files Reference

```
kubernetes_cell_platform/
├── l0_infrastructure/          # Terraform + Talos configs
│   └── terraform/
│       └── providers/proxmox/
│           └── (Cilium inline manifests in Talos config)
│
├── l1_platform/                # This project
│   ├── metallb/               # MetalLB manifests
│   ├── external-dns/          # External-DNS manifests
│   ├── test-service/          # Validation service
│   └── generated/
│       └── L1_COMPONENT_OWNERSHIP.md  # This file
│
└── l2_core-platform/           # GitOps, Policy, Mesh
    ├── argocd/
    ├── applications/
    ├── configs/
    └── ...
```

---

**Maintainer**: Infrastructure Team
**Last Updated**: 2025-12-30
