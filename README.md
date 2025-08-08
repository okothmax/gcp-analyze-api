# GCP Private Cloud Run FastAPI Analyze API

A minimal, production-ready example that deploys a Python FastAPI service to a private (internal-only) Cloud Run service on Google Cloud using Terraform and GitHub Actions CI/CD.

The API exposes a single endpoint:
- POST /analyze

Request:
```json
{"text": "I love cloud engineering!"}
```

Response:
```json
{
  "original_text": "I love cloud engineering!",
  "word_count": 4,
  "character_count": 25
}
```

Note: `character_count` includes all characters, including spaces and punctuation (i.e., `len(text)`).


## Architecture Overview

Services used:
- Cloud Run (fully managed) — private, internal-only ingress
- Artifact Registry — container image storage
- IAM — least-privilege service account for runtime
- Cloud Build API (enabled) — required by Cloud Run/infra
- Terraform — Infrastructure as Code
- GitHub Actions — CI/CD pipeline

Text diagram:
```
[GitHub Actions]
   |  (WIF auth)
   v
[Artifact Registry]  <--- Docker push
   ^
   | (image pull, reader role)
[Cloud Run (internal-only)]  <--- Terraform deploys service & IAM
          ^
          | (POST /analyze, internal ingress only)
      Private clients (VPC / internal LB / authorized callers)
```


## Design Decisions

- FastAPI + Uvicorn for simplicity and speed.
- Docker image based on python:3.12-slim with non-root user for security.
- Cloud Run v2 service configured with `INGRESS_TRAFFIC_INTERNAL_ONLY` to prevent public access.
- Dedicated runtime service account with `artifactregistry.reader` to pull images.
- Terraform variables parameterize project, region, repository, and service names.
- GitHub Actions uses Workload Identity Federation (no long-lived keys) to build, push, and run Terraform apply. Image tag is the commit SHA and passed to Terraform via `-var=image=...`.


## Setup and Deployment Instructions

Prerequisites:
- A GCP project you control (project ID available). This repo defaults to using an existing project.
- Billing enabled and owner/editor permissions for initial setup.
- Organization admins can optionally adapt Terraform to create a new project (not enabled by default here).
- GitHub repository to host this code.

### 1) Clone and review
```
git clone <this_repo_url>
cd gcp-analyze-api
```

### 2) Local test (optional)
```
python -m venv .venv
source .venv/bin/activate
pip install -r analyzer-app/requirements.txt
uvicorn analyzer-app.app.main:app --host 0.0.0.0 --port 8080
# curl example
curl -s -X POST http://127.0.0.1:8080/analyze -H 'Content-Type: application/json' -d '{"text":"I love cloud engineering!"}' | jq
```

### 3) Configure GCP resources with Terraform (first-time bootstrap)
Create a `terraform/terraform.tfvars` file:
```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
repo_name  = "analyze-api"
service_name = "analyze-api"
```
Initialize and apply:
```
cd terraform
terraform init
terraform apply -var-file=terraform.tfvars
```
Outputs include the Cloud Run service URI (internal). The service is not publicly accessible.

### 4) Configure GitHub Actions (Workload Identity Federation)
In GCP, set up WIF for GitHub:
- Create a workload identity pool and provider for GitHub (repo-level).
- Create or reuse a deploy service account with permissions: `roles/artifactregistry.writer`, `roles/run.admin`, `roles/iam.serviceAccountUser`, and `roles/storage.admin` (or least you need for Terraform state if you later move to GCS backend). For simplicity with local state, `storage.admin` is optional.
- Grant the provider permission to impersonate the deploy service account.

In GitHub repo Settings → Secrets and variables → Actions, define:
- `GCP_WORKLOAD_IDENTITY_PROVIDER` (full resource name)
- `GCP_SERVICE_ACCOUNT` (email of the deploy SA)
- `GCP_PROJECT_ID`
- `GCP_REGION` (e.g., us-central1)
- `ARTIFACT_REPO` (e.g., analyze-api)
- `CLOUD_RUN_SERVICE` (e.g., analyze-api)

On push to main, the workflow will:
- Lint Python and Terraform
- Build Docker image
- Push to Artifact Registry
- Run `terraform apply` with the new image tag

### 5) Calling the private service
Since ingress is internal-only, you must call it from within your VPC or via an internal load balancer/authorized network. For testing, you can temporarily allow your identity to invoke (still internal) and use the Cloud Run proxy from a VM with access, or expose through an internal HTTPS load balancer.


## Repository Structure
```
.
├─ analyzer-app/
│  ├─ app/
│  │  ├─ __init__.py
│  │  └─ main.py
│  ├─ requirements.txt
│  ├─ Dockerfile
│  └─ .dockerignore
├─ terraform/
│  ├─ main.tf
│  ├─ variables.tf
│  ├─ outputs.tf
│  └─ versions.tf
├─ .github/
│  └─ workflows/
│     └─ ci-cd.yml
└─ README.md
```


## NB
- Terraform state is local by default. In Production, migrate to a remote backend (e.g., GCS) with state locking.
- This sample does not create a new GCP project by default to avoid requiring org/billing setup.

