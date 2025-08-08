provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
  ])
  project = var.project_id
  service = each.value
}

# Artifact Registry (Docker)
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = var.repo_name
  description   = "Container images for analyze API"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

# Cloud Run runtime service account (least-privilege)
resource "google_service_account" "run_sa" {
  account_id   = "${var.service_name}-sa"
  display_name = "Cloud Run runtime SA for ${var.service_name}"
}

# Allow runtime SA to pull from Artifact Registry
resource "google_project_iam_member" "ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# Cloud Run v2 service (internal only)
resource "google_cloud_run_v2_service" "service" {
  name     = var.service_name
  location = var.region

  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = google_service_account.run_sa.email

    containers {
      image = var.image
      ports {
        name           = "http1"
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
      env {
        name  = "PORT"
        value = "8080"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_artifact_registry_repository.repo,
  ]
}

# Optionally allow specific principals to invoke (still internal ingress)
resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = toset(var.allow_invokers)
  name     = google_cloud_run_v2_service.service.name
  location = google_cloud_run_v2_service.service.location
  role     = "roles/run.invoker"
  member   = each.value
}
