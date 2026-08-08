output "bucket" {
  description = "State bucket. Pass to environments as -backend-config=\"bucket=...\"."
  value       = google_storage_bucket.state.name
}
