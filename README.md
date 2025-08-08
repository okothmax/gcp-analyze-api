# GCP Private Cloud Run FastAPI Analyze API

A minimal, production-ready example that deploys a Python FastAPI service to a private (internal-only) Cloud Run service on Google Cloud using Terraform and GitHub Actions CI/CD. It uses **Workload Identity Federation** to authenticate GitHub Actions without storing GCP service account keys.

---

## API Overview

The API exposes a single endpoint:
- **POST** `/analyze`

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

Note: `character_count` includes all characters, including spaces and punctuation (`len(text)`).

## Architecture Overview

Services used:
- **Cloud Run** — internal-only ingress
- **Artifact Registry** — container image storage  
- **IAM** — secure service accounts & workload identity federation
- **Terraform** — Infrastructure as Code
- **GitHub Actions** — CI/CD with WIF (Workload Identity Federation)
- **IAM Service Account Credentials API** — for impersonation

Text diagram:
```
[GitHub Actions]
   |  (OIDC token)
   v
[Workload Identity Provider] -- maps --> [Deploy Service Account]
   |
   v
[gcloud, terraform, docker build]
   |
   v
[Artifact Registry] <--- Docker push
   ^
   | (runtime pull)
[Cloud Run (internal-only)]  <--- terraform apply
          ^
          | (POST /analyze)
   Private clients (VPC / internal LB / auth)
```

## Setup & Deployment Instructions

### Prerequisites
- GCP project (with billing enabled)
- `gcloud` CLI authenticated as project owner
- GitHub repository with this code
- Terraform and Docker installed locally

### 1) Authenticate to GCP in your terminal
If you haven't yet, run:
```bash
gcloud init
```
It will:
- Open a browser to log in
- Let you pick a project
- Set the default region

After gcloud init, confirm the correct project is set:
```bash
gcloud config get-value project
```
If needed:
```bash
gcloud config set project YOUR_PROJECT_ID
```

### 2) Enable Required APIs
Run this in your terminal:
```bash
gcloud services enable iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com
```
This enables:
- IAM
- Project access controls
- Artifact Registry (for Docker images)
- Cloud Run

### 3) Create a GCP Service Account for GitHub Actions
```bash
gcloud iam service-accounts create github-actions-deployer \
  --display-name="GitHub Actions Deployer"
```
Then get the email for the service account:
```bash
gcloud iam service-accounts list
```
Copy the full email like:
`github-actions-deployer@your-project-id.iam.gserviceaccount.com`

We'll use it in later steps.

### 4) Grant Roles to the Service Account
Give the service account the needed permissions:
```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-actions-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.admin"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-actions-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-actions-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```
Replace YOUR_PROJECT_ID with your actual project ID.

### 5) Create a Workload Identity Pool
```bash
gcloud iam workload-identity-pools create github-pool \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

### 6) Create a Provider inside that Pool
```bash
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

### 7) Bind the Repo to the Service Account
Replace:
- PROJECT_NUMBER (you can get it with `gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"`)
- GITHUB_OWNER/REPO_NAME (e.g., octopus/gcp-analyze-api)

```bash
gcloud iam service-accounts add-iam-policy-binding github-actions-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/GITHUB_OWNER/REPO_NAME"
```

### 8) Clone and Review
```bash
git clone <your_repo_url>
cd gcp-analyze-api
```

### 9) Local Test (Optional)
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r analyzer-app/requirements.txt
uvicorn analyzer-app.app.main:app --host 0.0.0.0 --port 8080

# test locally
curl -s -X POST http://127.0.0.1:8080/analyze \
  -H 'Content-Type: application/json' \
  -d '{"text":"I love cloud engineering!"}' | jq
```

### 10) Configure GCP Resources with Terraform
Create a file `terraform/terraform.tfvars`:
```hcl
project_id   = "your-project-id"
region       = "us-central1"
repo_name    = "analyze-api"
service_name = "analyze-api"
```

Initialize and apply:
```bash
cd terraform
terraform init
terraform apply -var-file=terraform.tfvars
```

Terraform provisions:
- Artifact Registry repo
- Private Cloud Run service
- Runtime service account with least privilege

### 11) Configure GitHub Actions Secrets
In GitHub repository → Settings > Secrets and variables > Actions, add:

| Name | Value |
|------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | `github-actions-deployer@your-project-id.iam.gserviceaccount.com` |
| `GCP_PROJECT_ID` | `your-project-id` |
| `GCP_REGION` | `us-central1` |
| `ARTIFACT_REPO` | `analyze-api` |
| `CLOUD_RUN_SERVICE` | `analyze-api` |

### 12) GitHub Actions Workflow
On push to main, the `.github/workflows/ci-cd.yml` workflow will:
1. Authenticate with GCP via WIF
2. Lint Python and Terraform code
3. Run pytest tests
4. Build Docker image
5. Push to Artifact Registry
6. Deploy to Cloud Run using `terraform apply`

### 13) Test the Private Service
Since the Cloud Run service is internal-only:
- You need to call it from an internal GCP VM, VPC connector, or internal LB
- You may temporarily allow your identity to invoke:
```bash
gcloud run services add-iam-policy-binding analyze-api \
  --region=us-central1 \
  --member=user:your-email@gmail.com \
  --role=roles/run.invoker
```
- Use the Cloud Run proxy if needed for local development/testing.


## Repository Structure
```
.
├─ analyzer-app/
│  ├─ app/
│  │  ├─ __init__.py
│  │  └─ main.py
│  ├─ test_main.py
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

## Notes
- **Terraform state is local by default.** For production, configure a GCS remote backend with locking.
- **This example doesn't create a new GCP project** (to avoid org/billing constraints).
- **Make sure `iamcredentials.googleapis.com` is enabled** to allow impersonation via WIF:
```bash
gcloud services enable iamcredentials.googleapis.com
```

## Troubleshooting

- **403 SERVICE_DISABLED**: Make sure all required APIs are enabled.
- **NOT_FOUND service account**: Ensure the SA exists and email is correct.
- **PERMISSION_DENIED**: Check IAM roles and WIF provider bindings.
- **Terraform failures**: Recheck `terraform.tfvars`, and service account permissions.
- **GitHub Actions auth issues**: Verify WIF provider configuration and repository mapping.

## Status
- Successfully deployed with private Cloud Run  
- WIF setup for GitHub Actions  
- No service account keys used  
- Secure internal-only inference endpoint  
- Comprehensive test suite (5 pytest tests)  
- Production-ready CI/CD pipeline
