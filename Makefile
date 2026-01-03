# ============================================================================
# L1 Cluster Platform - Makefile
# ============================================================================
# Core platform services: CNI, LoadBalancer, DNS, Autoscaling
# ============================================================================

.PHONY: help deploy-all deploy-metallb deploy-external-dns deploy-karpenter
.PHONY: deploy-nginx-ingress deploy-metrics-server deploy-test-service status verify clean
.PHONY: karpenter-secrets karpenter-install karpenter-resources
.PHONY: karpenter-status karpenter-logs karpenter-test karpenter-uninstall
.PHONY: linkerd-status linkerd-check
.PHONY: deploy-storage deploy-cert-manager deploy-minio storage-status cert-manager-status minio-status
.PHONY: show-config

# Default target
.DEFAULT_GOAL := help

# ============================================================================
# Configuration
# ============================================================================

KUBECTL := kubectl
HELM := helm
YQ := yq

# Cell Configuration (read from parent repo)
CELL_CONFIG := ../meta/cell-config.yaml

# Dynamic values from cell-config.yaml (with defaults)
NFS_SERVER := $(shell $(YQ) '.storage.nfs.server // "192.168.2.50"' $(CELL_CONFIG) 2>/dev/null || echo "192.168.2.50")
NFS_PATH := $(shell $(YQ) '.storage.nfs.path // "/volume2/shared/k8s-storage"' $(CELL_CONFIG) 2>/dev/null || echo "/volume2/shared/k8s-storage")
STORAGE_CLASS := $(shell $(YQ) '.storage.class // "nfs-client"' $(CELL_CONFIG) 2>/dev/null || echo "nfs-client")
DOMAIN_BASE := $(shell $(YQ) '.domain.base // "lab.home"' $(CELL_CONFIG) 2>/dev/null || echo "lab.home")
TLS_ISSUER := $(shell $(YQ) '.ingress.tls.issuer // "internal-ca"' $(CELL_CONFIG) 2>/dev/null || echo "internal-ca")
MINIO_API_HOST := $(shell $(YQ) '.services.minio.api_host // "minio.lab.home"' $(CELL_CONFIG) 2>/dev/null || echo "minio.lab.home")
MINIO_CONSOLE_HOST := $(shell $(YQ) '.services.minio.console_host // "minio-console.lab.home"' $(CELL_CONFIG) 2>/dev/null || echo "minio-console.lab.home")

# Component Versions
METALLB_VERSION := 0.15.3
NGINX_VERSION := 4.14.1
METRICS_SERVER_VERSION := 3.13.0
LINKERD_VERSION := edge-25.12.3
KARPENTER_VERSION := 0.4.1
CERT_MANAGER_VERSION := 1.16.2
NFS_PROVISIONER_VERSION := 4.0.18
MINIO_VERSION := 5.3.0

# Helm Repositories
METALLB_REPO := https://metallb.github.io/metallb
NGINX_REPO := https://kubernetes.github.io/ingress-nginx
METRICS_SERVER_REPO := https://kubernetes-sigs.github.io/metrics-server/
KARPENTER_CHART := oci://ghcr.io/sergelogvinov/charts/karpenter-provider-proxmox
JETSTACK_REPO := https://charts.jetstack.io
NFS_PROVISIONER_REPO := https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
MINIO_REPO := https://charts.min.io/

# Colors for output
COLOR_RESET := \033[0m
COLOR_BOLD := \033[1m
COLOR_GREEN := \033[32m
COLOR_YELLOW := \033[33m
COLOR_BLUE := \033[34m
COLOR_CYAN := \033[36m
COLOR_RED := \033[31m

# ============================================================================
# Help
# ============================================================================

help: ## Show this help message
	@echo "$(COLOR_BOLD)L1 Cluster Platform$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)===================$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Quick Start:$(COLOR_RESET)"
	@echo "  $(COLOR_GREEN)make deploy-all$(COLOR_RESET)      - Deploy all L1 services"
	@echo "  $(COLOR_GREEN)make status$(COLOR_RESET)          - Check all services"
	@echo "  $(COLOR_GREEN)make verify$(COLOR_RESET)          - Verify deployment"
	@echo ""
	@echo "$(COLOR_BOLD)Individual Services:$(COLOR_RESET)"
	@echo "  make deploy-metallb        - Deploy MetalLB LoadBalancer (Helm)"
	@echo "  make deploy-nginx-ingress  - Deploy NGINX Ingress Controller (Helm)"
	@echo "  make deploy-metrics-server - Deploy metrics-server (Helm)"
	@echo "  make deploy-external-dns   - Deploy external-dns (Kustomize)"
	@echo "  make deploy-karpenter      - Deploy Karpenter autoscaler (Helm)"
	@echo "  make deploy-test-service   - Deploy test whoami service"
	@echo ""
	@echo "$(COLOR_BOLD)Storage & TLS:$(COLOR_RESET)"
	@echo "  make deploy-cert-manager   - Deploy cert-manager + internal CA (Helm)"
	@echo "  make deploy-storage        - Deploy NFS provisioner (Helm)"
	@echo "  make deploy-minio          - Deploy MinIO S3 storage (Helm)"
	@echo ""
	@echo "$(COLOR_BOLD)Service Mesh (Linkerd - CLI managed):$(COLOR_RESET)"
	@echo "  make linkerd-status        - Show Linkerd status"
	@echo "  make linkerd-check         - Run Linkerd health check"
	@echo ""
	@echo "$(COLOR_BOLD)Karpenter Management:$(COLOR_RESET)"
	@echo "  make karpenter-status     - Show Karpenter status"
	@echo "  make karpenter-logs       - View Karpenter logs"
	@echo "  make karpenter-test       - Test autoscaling"
	@echo "  make karpenter-uninstall  - Remove Karpenter"
	@echo ""
	@echo "$(COLOR_BOLD)Utilities:$(COLOR_RESET)"
	@echo "  make show-config          - Show cell configuration values"
	@echo "  make clean                - Remove test resources"

# ============================================================================
# Cell Configuration
# ============================================================================

show-config: ## Show cell configuration values
	@echo "$(COLOR_BOLD)📋 Cell Configuration$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)=====================$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Source:$(COLOR_RESET) $(CELL_CONFIG)"
	@echo ""
	@echo "$(COLOR_BOLD)Storage:$(COLOR_RESET)"
	@echo "  NFS Server:    $(NFS_SERVER)"
	@echo "  NFS Path:      $(NFS_PATH)"
	@echo "  StorageClass:  $(STORAGE_CLASS)"
	@echo ""
	@echo "$(COLOR_BOLD)Domain & TLS:$(COLOR_RESET)"
	@echo "  Base Domain:   $(DOMAIN_BASE)"
	@echo "  TLS Issuer:    $(TLS_ISSUER)"
	@echo ""
	@echo "$(COLOR_BOLD)MinIO:$(COLOR_RESET)"
	@echo "  API Host:      $(MINIO_API_HOST)"
	@echo "  Console Host:  $(MINIO_CONSOLE_HOST)"

# ============================================================================
# Full Deployment
# ============================================================================

deploy-all: deploy-metallb deploy-nginx-ingress deploy-metrics-server deploy-external-dns deploy-test-service ## Deploy all L1 services
	@echo ""
	@echo "$(COLOR_GREEN)$(COLOR_BOLD)✅ L1 Cluster Platform deployed!$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Deployed services:$(COLOR_RESET)"
	@echo "  ✅ MetalLB LoadBalancer"
	@echo "  ✅ NGINX Ingress Controller"
	@echo "  ✅ metrics-server"
	@echo "  ✅ external-dns"
	@echo "  ✅ Test service (whoami)"
	@echo ""
	@echo "$(COLOR_YELLOW)Note: These require manual deployment:$(COLOR_RESET)"
	@echo "  $(COLOR_CYAN)make deploy-karpenter$(COLOR_RESET)  - Node autoscaling"
	@echo "  $(COLOR_CYAN)linkerd install | kubectl apply -f -$(COLOR_RESET)  - Service mesh"

# ============================================================================
# Individual Service Deployments
# ============================================================================

deploy-metallb: ## Deploy MetalLB LoadBalancer via Helm
	@echo "$(COLOR_BOLD)📦 Deploying MetalLB $(METALLB_VERSION)...$(COLOR_RESET)"
	@$(HELM) repo add metallb $(METALLB_REPO) 2>/dev/null || true
	@$(HELM) repo update metallb
	@$(HELM) upgrade -i metallb metallb/metallb \
		--namespace metallb-system \
		--create-namespace \
		--version $(METALLB_VERSION) \
		-f metallb/helm/metallb-values.yaml \
		--wait --timeout 5m
	@echo "$(COLOR_YELLOW)⏳ Applying MetalLB configuration...$(COLOR_RESET)"
	@$(KUBECTL) apply -f metallb/ipaddresspool.yaml
	@$(KUBECTL) apply -f metallb/l2advertisement.yaml
	@echo "$(COLOR_GREEN)✅ MetalLB $(METALLB_VERSION) deployed$(COLOR_RESET)"

deploy-nginx-ingress: ## Deploy NGINX Ingress Controller via Helm
	@echo "$(COLOR_BOLD)📦 Deploying NGINX Ingress $(NGINX_VERSION)...$(COLOR_RESET)"
	@$(HELM) repo add ingress-nginx $(NGINX_REPO) 2>/dev/null || true
	@$(HELM) repo update ingress-nginx
	@$(HELM) upgrade -i ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx \
		--create-namespace \
		--version $(NGINX_VERSION) \
		-f nginx-ingress/helm/nginx-ingress-values.yaml \
		--wait --timeout 5m
	@echo "$(COLOR_GREEN)✅ NGINX Ingress $(NGINX_VERSION) deployed$(COLOR_RESET)"

deploy-external-dns: ## Deploy external-dns
	@echo "$(COLOR_BOLD)📦 Deploying external-dns...$(COLOR_RESET)"
	@$(KUBECTL) apply -k external-dns/
	@echo "$(COLOR_YELLOW)⏳ Waiting for external-dns to be ready...$(COLOR_RESET)"
	@$(KUBECTL) wait --for=condition=ready pod -l app.kubernetes.io/name=external-dns -n external-dns --timeout=120s 2>/dev/null || true
	@echo "$(COLOR_GREEN)✅ external-dns deployed$(COLOR_RESET)"

deploy-metrics-server: ## Deploy metrics-server via Helm
	@echo "$(COLOR_BOLD)📦 Deploying metrics-server $(METRICS_SERVER_VERSION)...$(COLOR_RESET)"
	@$(HELM) repo add metrics-server $(METRICS_SERVER_REPO) 2>/dev/null || true
	@$(HELM) repo update metrics-server
	@$(HELM) upgrade -i metrics-server metrics-server/metrics-server \
		--namespace kube-system \
		--version $(METRICS_SERVER_VERSION) \
		-f metrics-server/helm/metrics-server-values.yaml \
		--wait --timeout 5m
	@echo "$(COLOR_GREEN)✅ metrics-server $(METRICS_SERVER_VERSION) deployed$(COLOR_RESET)"

deploy-test-service: ## Deploy test whoami service
	@echo "$(COLOR_BOLD)📦 Deploying test service...$(COLOR_RESET)"
	@$(KUBECTL) apply -f test-service/whoami.yaml
	@echo "$(COLOR_GREEN)✅ Test service deployed$(COLOR_RESET)"

# ============================================================================
# Karpenter Deployment
# ============================================================================

deploy-karpenter: karpenter-secrets karpenter-install karpenter-resources ## Deploy Karpenter autoscaler
	@echo ""
	@echo "$(COLOR_GREEN)$(COLOR_BOLD)✅ Karpenter deployment complete!$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Hybrid worker strategy:$(COLOR_RESET)"
	@echo "  • Static workers (Terraform): baseline capacity"
	@echo "  • Dynamic workers (Karpenter): burst capacity (0-10 nodes)"
	@echo ""
	@echo "$(COLOR_BOLD)Verify deployment:$(COLOR_RESET)"
	@echo "  $(COLOR_CYAN)make karpenter-status$(COLOR_RESET)"

karpenter-secrets: ## Create Karpenter secrets
	@echo "$(COLOR_BOLD)🔐 Creating Karpenter secrets...$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)⚠️  Ensure secrets have been updated with real values!$(COLOR_RESET)"
	@$(KUBECTL) apply -f karpenter/secret-proxmox-credentials.yaml
	@$(KUBECTL) apply -f karpenter/secret-talos-template.yaml
	@$(KUBECTL) apply -f karpenter/secret-talos-values.yaml
	@echo "$(COLOR_GREEN)✅ Secrets created$(COLOR_RESET)"

karpenter-install: ## Install Karpenter via Helm
	@echo "$(COLOR_BOLD)📦 Installing Karpenter $(KARPENTER_VERSION)...$(COLOR_RESET)"
	@$(HELM) upgrade -i karpenter-proxmox $(KARPENTER_CHART) \
		--namespace kube-system \
		--version $(KARPENTER_VERSION) \
		-f karpenter/helm/karpenter-proxmox-values.yaml \
		--wait --timeout 5m
	@echo "$(COLOR_GREEN)✅ Karpenter installed$(COLOR_RESET)"

karpenter-resources: ## Deploy Karpenter CRDs
	@echo "$(COLOR_BOLD)⚙️  Deploying Karpenter resources...$(COLOR_RESET)"
	@$(KUBECTL) apply -f karpenter/proxmox-unmanaged-template.yaml
	@sleep 10
	@$(KUBECTL) apply -f karpenter/proxmox-nodeclass.yaml
	@$(KUBECTL) apply -f karpenter/nodepool-burst.yaml
	@echo "$(COLOR_GREEN)✅ Karpenter resources deployed$(COLOR_RESET)"

karpenter-status: ## Show Karpenter status
	@echo "$(COLOR_BOLD)📊 Karpenter Status$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)===================$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Controller:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n kube-system -l app.kubernetes.io/name=karpenter-proxmox 2>/dev/null || echo "  Not installed"
	@echo ""
	@echo "$(COLOR_BOLD)Node Pools:$(COLOR_RESET)"
	@$(KUBECTL) get NodePool -o wide 2>/dev/null || echo "  None found"
	@echo ""
	@echo "$(COLOR_BOLD)Node Claims:$(COLOR_RESET)"
	@$(KUBECTL) get NodeClaim -o wide 2>/dev/null || echo "  None active"

karpenter-logs: ## View Karpenter logs
	@$(KUBECTL) logs -n kube-system -l app.kubernetes.io/name=karpenter-proxmox --tail=100 -f

karpenter-test: ## Test Karpenter scaling
	@echo "$(COLOR_BOLD)🧪 Testing Karpenter Scaling...$(COLOR_RESET)"
	@$(KUBECTL) apply -f karpenter/test/test-deployment.yaml
	@echo ""
	@echo "$(COLOR_YELLOW)Watch node provisioning:$(COLOR_RESET)"
	@echo "  $(COLOR_CYAN)kubectl get nodeclaims -w$(COLOR_RESET)"

karpenter-uninstall: ## Remove Karpenter
	@echo "$(COLOR_BOLD)🗑️  Removing Karpenter...$(COLOR_RESET)"
	@$(KUBECTL) delete nodeclaims --all 2>/dev/null || true
	@$(KUBECTL) delete -f karpenter/nodepool-burst.yaml 2>/dev/null || true
	@$(KUBECTL) delete -f karpenter/proxmox-nodeclass.yaml 2>/dev/null || true
	@$(KUBECTL) delete -f karpenter/proxmox-unmanaged-template.yaml 2>/dev/null || true
	@$(HELM) uninstall karpenter-proxmox -n kube-system 2>/dev/null || true
	@$(KUBECTL) delete secret -n kube-system karpenter-provider-proxmox karpenter-talos-template karpenter-talos-values 2>/dev/null || true
	@echo "$(COLOR_GREEN)✅ Karpenter removed$(COLOR_RESET)"

# ============================================================================
# Linkerd (CLI-managed)
# ============================================================================

linkerd-status: ## Show Linkerd status
	@echo "$(COLOR_BOLD)📊 Linkerd Status$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)=================$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Control Plane:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n linkerd 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)Viz Extension:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n linkerd-viz 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_YELLOW)Note: Linkerd is managed via linkerd CLI, not Helm$(COLOR_RESET)"
	@echo "  Install: linkerd install | kubectl apply -f -"
	@echo "  Upgrade: linkerd upgrade | kubectl apply -f -"

linkerd-check: ## Run Linkerd health check
	@echo "$(COLOR_BOLD)🔍 Running Linkerd health check...$(COLOR_RESET)"
	@linkerd check 2>/dev/null || echo "$(COLOR_YELLOW)linkerd CLI not installed or check failed$(COLOR_RESET)"

# ============================================================================
# Storage, TLS, and S3
# ============================================================================

deploy-cert-manager: ## Deploy cert-manager + internal CA
	@echo "$(COLOR_BOLD)📦 Deploying cert-manager $(CERT_MANAGER_VERSION)...$(COLOR_RESET)"
	@$(HELM) repo add jetstack $(JETSTACK_REPO) 2>/dev/null || true
	@$(HELM) repo update jetstack
	@$(KUBECTL) apply -k cert-manager/
	@$(HELM) upgrade -i cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--version v$(CERT_MANAGER_VERSION) \
		-f cert-manager/helm/cert-manager-values.yaml \
		--wait --timeout 5m
	@echo "$(COLOR_YELLOW)⏳ Creating internal CA bootstrap chain...$(COLOR_RESET)"
	@sleep 5
	@$(KUBECTL) apply -f cert-manager/ca/ca-issuer.yaml
	@echo "$(COLOR_YELLOW)⏳ Waiting for CA certificate to be ready...$(COLOR_RESET)"
	@sleep 15
	@$(KUBECTL) get certificate homelab-ca -n cert-manager || true
	@$(KUBECTL) get clusterissuers || true
	@echo "$(COLOR_GREEN)✅ cert-manager $(CERT_MANAGER_VERSION) deployed with internal CA$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_YELLOW)To trust the CA on your machine:$(COLOR_RESET)"
	@echo "  $(COLOR_CYAN)kubectl get secret homelab-ca-key-pair -n cert-manager -o jsonpath='{.data.tls\\.crt}' | base64 -d > homelab-ca.crt$(COLOR_RESET)"
	@echo "  $(COLOR_CYAN)sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homelab-ca.crt$(COLOR_RESET)"

cert-manager-status: ## Show cert-manager status
	@echo "$(COLOR_BOLD)📊 cert-manager Status$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)======================$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Controller:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n cert-manager 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)ClusterIssuers:$(COLOR_RESET)"
	@$(KUBECTL) get clusterissuers 2>/dev/null || echo "  None found"
	@echo ""
	@echo "$(COLOR_BOLD)Certificates:$(COLOR_RESET)"
	@$(KUBECTL) get certificates -A 2>/dev/null || echo "  None found"

deploy-storage: ## Deploy NFS provisioner
	@echo "$(COLOR_BOLD)📦 Deploying NFS Provisioner $(NFS_PROVISIONER_VERSION)...$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)  NFS Server: $(NFS_SERVER)$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)  NFS Path:   $(NFS_PATH)$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)  StorageClass: $(STORAGE_CLASS)$(COLOR_RESET)"
	@$(HELM) repo add nfs-subdir-external-provisioner $(NFS_PROVISIONER_REPO) 2>/dev/null || true
	@$(HELM) repo update nfs-subdir-external-provisioner
	@$(KUBECTL) apply -k storage/
	@$(HELM) upgrade -i nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
		--namespace nfs-provisioner \
		--version $(NFS_PROVISIONER_VERSION) \
		-f storage/helm/nfs-provisioner-values.yaml \
		--set nfs.server=$(NFS_SERVER) \
		--set nfs.path=$(NFS_PATH) \
		--set storageClass.name=$(STORAGE_CLASS) \
		--wait --timeout 5m
	@echo "$(COLOR_GREEN)✅ NFS Provisioner $(NFS_PROVISIONER_VERSION) deployed$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)StorageClass:$(COLOR_RESET)"
	@$(KUBECTL) get storageclass

storage-status: ## Show storage status
	@echo "$(COLOR_BOLD)📊 Storage Status$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)=================$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)NFS Provisioner:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n nfs-provisioner 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)StorageClasses:$(COLOR_RESET)"
	@$(KUBECTL) get storageclass 2>/dev/null || echo "  None found"
	@echo ""
	@echo "$(COLOR_BOLD)PersistentVolumeClaims:$(COLOR_RESET)"
	@$(KUBECTL) get pvc -A 2>/dev/null || echo "  None found"

deploy-minio: ## Deploy MinIO S3 storage
	@echo "$(COLOR_BOLD)📦 Deploying MinIO $(MINIO_VERSION)...$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)  API Host:     $(MINIO_API_HOST)$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)  Console Host: $(MINIO_CONSOLE_HOST)$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)  TLS Issuer:   $(TLS_ISSUER)$(COLOR_RESET)"
	@echo "$(COLOR_YELLOW)⚠️  Requires: cert-manager and storage (NFS) deployed first$(COLOR_RESET)"
	@$(HELM) repo add minio $(MINIO_REPO) 2>/dev/null || true
	@$(HELM) repo update minio
	@$(KUBECTL) apply -k minio/
	@$(HELM) upgrade -i minio minio/minio \
		--namespace minio \
		--version $(MINIO_VERSION) \
		-f minio/helm/minio-values.yaml \
		--set ingress.hosts[0]=$(MINIO_API_HOST) \
		--set ingress.tls[0].hosts[0]=$(MINIO_API_HOST) \
		--set ingress.annotations."cert-manager\.io/cluster-issuer"=$(TLS_ISSUER) \
		--set consoleIngress.hosts[0]=$(MINIO_CONSOLE_HOST) \
		--set consoleIngress.tls[0].hosts[0]=$(MINIO_CONSOLE_HOST) \
		--set consoleIngress.annotations."cert-manager\.io/cluster-issuer"=$(TLS_ISSUER) \
		--set persistence.storageClass=$(STORAGE_CLASS) \
		--set environment.MINIO_BROWSER_REDIRECT_URL=https://$(MINIO_CONSOLE_HOST) \
		--wait --timeout 10m
	@echo "$(COLOR_GREEN)✅ MinIO $(MINIO_VERSION) deployed$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Access:$(COLOR_RESET)"
	@echo "  API: https://$(MINIO_API_HOST)"
	@echo "  Console: https://$(MINIO_CONSOLE_HOST)"

minio-status: ## Show MinIO status
	@echo "$(COLOR_BOLD)📊 MinIO Status$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)===============$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)Pods:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n minio 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)Services:$(COLOR_RESET)"
	@$(KUBECTL) get svc -n minio 2>/dev/null || echo "  None found"
	@echo ""
	@echo "$(COLOR_BOLD)Ingresses:$(COLOR_RESET)"
	@$(KUBECTL) get ingress -n minio 2>/dev/null || echo "  None found"

# ============================================================================
# Status and Verification
# ============================================================================

status: ## Show status of all L1 services
	@echo "$(COLOR_BOLD)📊 L1 Cluster Platform Status$(COLOR_RESET)"
	@echo "$(COLOR_CYAN)==============================$(COLOR_RESET)"
	@echo ""
	@echo "$(COLOR_BOLD)MetalLB:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n metallb-system 2>/dev/null || echo "  Not deployed"
	@$(HELM) list -n metallb-system 2>/dev/null | grep metallb || echo "  (Helm release not found)"
	@echo ""
	@echo "$(COLOR_BOLD)NGINX Ingress:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n ingress-nginx 2>/dev/null || echo "  Not deployed"
	@$(HELM) list -n ingress-nginx 2>/dev/null | grep ingress || echo "  (Helm release not found)"
	@echo ""
	@echo "$(COLOR_BOLD)metrics-server:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n kube-system -l app.kubernetes.io/name=metrics-server 2>/dev/null || echo "  Not deployed"
	@$(HELM) list -n kube-system 2>/dev/null | grep metrics-server || echo "  (Helm release not found)"
	@echo ""
	@echo "$(COLOR_BOLD)external-dns:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n external-dns 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)Linkerd:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n linkerd 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)Linkerd-viz:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n linkerd-viz 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)Karpenter:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n kube-system -l app.kubernetes.io/name=karpenter-proxmox 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)cert-manager:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n cert-manager 2>/dev/null || echo "  Not deployed"
	@$(KUBECTL) get clusterissuers 2>/dev/null || echo "  (No issuers)"
	@echo ""
	@echo "$(COLOR_BOLD)NFS Provisioner:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n nfs-provisioner 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)MinIO:$(COLOR_RESET)"
	@$(KUBECTL) get pods -n minio 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)Test Service:$(COLOR_RESET)"
	@$(KUBECTL) get svc -n test-service 2>/dev/null || echo "  Not deployed"
	@echo ""
	@echo "$(COLOR_BOLD)StorageClasses:$(COLOR_RESET)"
	@$(KUBECTL) get storageclass 2>/dev/null || echo "  None found"
	@echo ""
	@echo "$(COLOR_BOLD)LoadBalancer IPs:$(COLOR_RESET)"
	@$(KUBECTL) get svc -A -o wide | grep LoadBalancer || echo "  None assigned"

verify: ## Verify L1 deployment
	@echo "$(COLOR_BOLD)🔍 Verifying L1 deployment...$(COLOR_RESET)"
	@echo ""
	@METALLB=$$($(KUBECTL) get pods -n metallb-system --no-headers 2>/dev/null | grep -c Running || echo 0); \
	DNS=$$($(KUBECTL) get pods -n external-dns --no-headers 2>/dev/null | grep -c Running || echo 0); \
	echo "MetalLB pods running: $$METALLB"; \
	echo "external-dns pods running: $$DNS"; \
	if [ $$METALLB -gt 0 ] && [ $$DNS -gt 0 ]; then \
		echo "$(COLOR_GREEN)✅ L1 verification passed$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)⚠️  Some services not running$(COLOR_RESET)"; \
	fi

clean: ## Remove test resources
	@echo "$(COLOR_BOLD)🧹 Cleaning test resources...$(COLOR_RESET)"
	@$(KUBECTL) delete namespace karpenter-test 2>/dev/null || true
	@$(KUBECTL) delete -f test-service/whoami.yaml 2>/dev/null || true
	@echo "$(COLOR_GREEN)✅ Test resources cleaned$(COLOR_RESET)"

# ============================================================================
# End of Makefile
# ============================================================================