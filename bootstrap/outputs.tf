output "state_bucket_name" {
  description = "S3 bucket name to use as the 'bucket' value in each environment's backend.tf"
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "DynamoDB table name to use as the 'dynamodb_table' value in each environment's backend.tf"
  value       = aws_dynamodb_table.terraform_locks.name
}
