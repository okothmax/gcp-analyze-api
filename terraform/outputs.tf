output "cloud_run_uri" {
  description = "Internal URI of the Cloud Run service"
  value       = google_cloud_run_v2_service.service.uri
}

output "service_account_email" {
  description = "Runtime service account email"
  value       = google_service_account.run_sa.email
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository"
  value       = google_artifact_registry_repository.repo.repository_id
}
