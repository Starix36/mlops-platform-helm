```markdown
MLOps Platform Engineering: Generic ML API Helm Chart

An enterprise-ready, generic Helm chart designed as part of an Internal Developer Platform (IDP) initiative. This project simplifies Machine Learning (ML) model deployments across Dev, Staging, and Production environments, bridging the operational gap between Data Science and Platform Engineering.

---

Repository Structure

```text
.
├── Makefile                     # Developer Experience (DevEx) target wrapper
├── README.md                    # Platform documentation and architecture overview
├── app/                         # Sample Python FastAPI ML service[cite: 2]
│   ├── Dockerfile               # Security-hardened non-root container image
│   ├── main.py                  # API endpoints (/ and /predict)
│   └── requirements.txt         # Lightweight dependencies (FastAPI, Uvicorn)
├── chart/                       # Generic Helm Chart[cite: 2]
│   ├── Chart.yaml               # Chart metadata and versioning
│   ├── values.yaml              # Default generic chart values
│   └── templates/               # Parameterized Kubernetes manifests
│       ├── _helpers.tpl         # Named template helpers
│       ├── deployment.yaml      # Workload specification with observability hooks
│       ├── service.yaml         # Internal ClusterIP routing
│       ├── secrets.yaml         # Encrypted environment variable mappings[cite: 3]
│       ├── hpa.yaml             # Horizontal Pod Autoscaler policies[cite: 3]
│       └── tests/               # Integrated Helm test suite[cite: 2]
│           └── test-connection.yaml
├── env-values/                  # Minimal environment overrides[cite: 2]
│   ├── dev-values.yaml          # Development configuration
│   ├── stg-values.yaml          # Staging configuration
│   └── prod-values.yaml         # Production configuration with autoscaling
├── iac/                         # Infrastructure as Code[cite: 2]
│   └── main.tf                  # Terraform snippet for Helm chart provisioning
└── .github/workflows/           # Continuous Integration & Delivery[cite: 2]
    └── helm-publish.yml         # GitHub Actions workflow for OCI packaging to GHCR

```

---

## 🧠 Platform Philosophy & Architecture

### 1. Developer Experience (DevEx) & Guardrails

ML Engineers (MLEs) should focus on feature engineering, model training, and evaluation—not on writing raw Kubernetes manifests. This platform provides a generic abstraction where MLEs only modify a concise `values-{env}.yaml` file to release their model.

Key Guardrails Enforced:

* **Security Context:** Containers run as non-root users (`mluser`) by default.
* **Observability Built-in:** Native `prometheus.io/scrape` annotations automatically register metrics scrapers.
* **Consistency:** The exact same chart binary is deployed across Dev, Staging, and Production, eliminating environment drift.

### 2. Multi-Environment Strategy

Environment isolation is achieved through minimal values files:

* **Dev (`dev-values.yaml`):** Single replica, low CPU/RAM footprint, autoscaling disabled.
* **Staging (`stg-values.yaml`):** Multi-replica, baseline resource limits, staging configurations.
* **Production (`prod-values.yaml`):** High availability (3+ replicas), aggressive CPU limits, auto-scaling enabled (1-10 replicas).



---

## ⚙️ Local Deployment Guide (Minikube)

Follow these steps to deploy and test the release locally on Minikube.

### 1. Start Cluster & Build API Image

```bash
# 1. Start Minikube
minikube start --driver=docker --cpus=2 --memory=3072

# 2. Build the lightweight Python ML API Docker image[cite: 2]
cd app
docker build -t my-ml-api:latest .

# 3. Load the image into the Minikube cluster daemon
minikube image load my-ml-api:latest
cd ..

```

### 2. Install the Helm Chart

Deploy the chart to the development environment:

```bash
helm install dev-release ./chart -f env-values/dev-values.yaml

```

Verify deployment status:

```bash
kubectl get pods
kubectl get svc

```

### 3. Access API from Local PC

Port-forward the Kubernetes service to your host machine:

```bash
kubectl port-forward service/dev-release-generic-ml-api 8000:8000

```

Open a second terminal window or browser to execute sample predictions:

```bash
# Check root API message
curl http://localhost:8000/

# Test ML Prediction endpoint
curl http://localhost:8000/predict

```

*Expected Output:* `{"prediction":[0.85,0.15],"model_version":"v1.0"}`

### 4. Execute Helm Test Suite

Validate service accessibility within the cluster using the built-in test suite:

```bash
helm test dev-release

```

*Expected Output:* `Phase: Succeeded` for `dev-release-generic-ml-api-test-connection`.

---

## 🔐 Secrets Management Approach

### Current Implementation

The chart renders Kubernetes native `Secret` manifests using base64 encoding from values files:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "generic-ml-api.fullname" . }}-secrets
type: Opaque
data:
  {{- range $key, $value := .Values.secrets }}
  {{ $key }}: {{ $value | b64enc | quote }}
  {{- end }}

```

### Production Recommendation

Base64 encoding is not encryption. Storing secrets in plain text inside Git repositories is an anti-pattern. In a production cloud ecosystem, I advocate for using **External Secrets Operator (ESO)** or **HashiCorp Vault Integration**:

1. Secrets are created and managed in AWS Secrets Manager, GCP Secret Manager, or HashiCorp Vault.
2. The Helm chart deploys an `ExternalSecret` Custom Resource Definition (CRD).
3. The External Secrets Operator synchronizes secret data directly into Kubernetes memory without exposing keys in Git or Helm values.



---

## 📈 Auto-Scaling Policies (HPA)

Horizontal Pod Autoscaling (HPA) is integrated into `chart/templates/hpa.yaml`. It scales workload replicas dynamically based on CPU utilization:

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "generic-ml-api.fullname" . }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "generic-ml-api.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
{{- end }}

```

Toggle HPA easily per environment:

* Dev: `autoscaling.enabled: false`

* Prod: `autoscaling.enabled: true` with `minReplicas: 3` and `maxReplicas: 10`


---

## 🏗️ Infrastructure as Code (IaC) Integration

The chart can be deployed programmatically using Terraform/Terragrunt. The snippet below (`iac/main.tf`) demonstrates how platform teams can manage deployments alongside underlying cloud infrastructure:

```hcl
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "ml_api_production" {
  name       = "ml-api-production"
  repository = "oci://ghcr.io/yourusername/charts"
  chart      = "generic-ml-api"
  version    = "0.1.0"
  namespace  = "production"

  # Load environment-specific values file
  values = [
    file("../env-values/prod-values.yaml")
  ]

  # Pass runtime secrets securely without hardcoding in Git
  set_sensitive {
    name  = "secrets.API_KEY"
    value = var.prod_api_key
  }
}

```

---

## 🔄 CI/CD & Version Control Strategy

### 1. Automated Pipeline (GitHub Actions)

The repository uses GitHub Actions (`.github/workflows/helm-publish.yml`) to automatically package and publish the chart as an Open Container Initiative (OCI) artifact to the GitHub Container Registry (GHCR):

* **Trigger:** Pushes to the `main` branch impacting the `chart/` directory.
* **Packaging:** `helm package ./chart`
* **Publish:** Pushes chart to `oci://ghcr.io/<owner>/charts/generic-ml-api`.



### 2. Branching & Versioning Principles

* **Chart Versioning:** Follows **Semantic Versioning (SemVer)** (`MAJOR.MINOR.PATCH` in `Chart.yaml`).


* `PATCH`: Bug fixes or backward-compatible template adjustments.
* `MINOR`: Adding new templates (e.g., ingress support, network policies).
* `MAJOR`: Breaking template changes requiring values file restructuring.


* **GitOps Deployment:** Actual deployments to target Kubernetes clusters should be managed by a pull-based GitOps engine such as **ArgoCD** or **FluxCD**, monitoring changes to `env-values/` files across environment branches.

```

```
