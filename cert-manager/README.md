# cert-manager

Automated TLS certificate management for Kubernetes.

## Components

- **cert-manager controller**: Issues and renews certificates
- **Internal CA**: Private certificate authority for internal services
- **Let's Encrypt issuers**: For public-facing services (optional)

## Installation

```bash
# Add Helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --values helm/cert-manager-values.yaml

# Apply issuers
kubectl apply -k .
```

## Available Issuers

| Issuer | Type | Use Case |
|--------|------|----------|
| `internal-ca` | CA | Internal services (default) |
| `letsencrypt-staging` | ACME | Testing public certs |
| `letsencrypt-prod` | ACME | Production public certs |

## Usage

### Request a Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-service-tls
  namespace: my-namespace
spec:
  secretName: my-service-tls
  issuerRef:
    name: internal-ca
    kind: ClusterIssuer
  commonName: my-service.lab.home
  dnsNames:
    - my-service.lab.home
```

### Ingress Annotation

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "internal-ca"
spec:
  tls:
    - hosts:
        - my-service.lab.home
      secretName: my-service-tls
```

## Trust the Internal CA

Export the CA certificate:

```bash
kubectl get secret homelab-ca-key-pair -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-ca.crt
```

### macOS

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain homelab-ca.crt
```

### Linux

```bash
sudo cp homelab-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### Windows

```powershell
Import-Certificate -FilePath homelab-ca.crt -CertStoreLocation Cert:\LocalMachine\Root
```

## Troubleshooting

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check certificate status
kubectl get certificates -A
kubectl describe certificate <name> -n <namespace>

# Check issuer status
kubectl get clusterissuers
kubectl describe clusterissuer internal-ca

# Check certificate requests
kubectl get certificaterequests -A
```
