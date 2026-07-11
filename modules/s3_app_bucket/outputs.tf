output "bucket_name" {
  description = "Name of the application S3 bucket"
  value       = aws_s3_bucket.app.id
}

output "bucket_arn" {
  description = "ARN of the application S3 bucket"
  value       = aws_s3_bucket.app.arn
}

output "irsa_role_arn" {
  description = "IAM role ARN to annotate on the Kubernetes ServiceAccount (eks.amazonaws.com/role-arn) so pods can access the bucket"
  value       = aws_iam_role.app_bucket_access.arn
}
