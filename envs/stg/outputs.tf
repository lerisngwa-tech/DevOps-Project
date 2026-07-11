output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing application images"
  value       = module.ecr.repository_url
}

output "app_bucket_name" {
  description = "Name of the application S3 bucket"
  value       = module.s3_app_bucket.bucket_name
}

output "app_bucket_irsa_role_arn" {
  description = "IAM role ARN to annotate on the app's ServiceAccount for S3 bucket access"
  value       = module.s3_app_bucket.irsa_role_arn
}

output "app_secret_name" {
  description = "Name of the application secret in Secrets Manager"
  value       = module.secrets_manager.secret_name
}

output "app_secret_irsa_role_arn" {
  description = "IAM role ARN to annotate on the app's ServiceAccount for Secrets Manager access"
  value       = module.secrets_manager.irsa_role_arn
}

output "app_log_group_name" {
  description = "CloudWatch log group name for application logs"
  value       = module.cloudwatch.app_log_group_name
}

output "db_endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = module.rds.db_instance_endpoint
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding live DB connection details"
  value       = module.rds.db_secret_arn
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret holding live DB connection details"
  value       = module.rds.db_secret_name
}

output "db_secret_irsa_role_arn" {
  description = "IAM role ARN the app assumes to read the DB secret"
  value       = module.rds.db_secret_irsa_role_arn
}

output "configure_kubectl" {
  description = "Command to update local kubeconfig for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
