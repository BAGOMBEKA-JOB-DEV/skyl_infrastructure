output "bucket" {
  description = "State bucket. Pass as -backend-config=\"bucket=...\"."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "Lock table. Pass as -backend-config=\"dynamodb_table=...\"."
  value       = aws_dynamodb_table.lock.name
}
