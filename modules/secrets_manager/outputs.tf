output "secret_arn" {
  description = "ARN of the application secret"
  value       = aws_secretsmanager_secret.app.arn
}

output "secret_name" {
  description = "Name of the application secret"
  value       = aws_secretsmanager_secret.app.name
}

output "irsa_role_arn" {
  description = "IAM role ARN to annotate on the Kubernetes ServiceAccount (eks.amazonaws.com/role-arn) so pods can read the secret"
  value       = aws_iam_role.secret_access.arn
}
