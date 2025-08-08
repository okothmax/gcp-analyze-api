variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "repo_name" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "analyze-api"
}

variable "service_name" {
  description = "Cloud Run service name"
  type        = string
  default     = "analyze-api"
}

variable "image" {
  description = "Full image reference (e.g., REGION-docker.pkg.dev/PROJECT/REPO/IMAGE:TAG)"
  type        = string
}

variable "allow_invokers" {
  description = "List of additional principals allowed to invoke the service (optional)"
  type        = list(string)
  default     = []
}
