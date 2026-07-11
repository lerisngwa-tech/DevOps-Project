output "db_instance_endpoint" {
  description = "Connection endpoint (host:port) of the RDS instance"
  value       = aws_db_instance.this.endpoint
}

output "db_instance_address" {
  description = "Hostname of the RDS instance, without the port"
  value       = aws_db_instance.this.address
}

output "db_instance_port" {
  description = "Port the RDS instance listens on"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database"
  value       = var.db_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding live DB connection details"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  description = "Name of the Secrets Manager secret holding live DB connection details"
  value       = aws_secretsmanager_secret.db.name
}

output "db_secret_irsa_role_arn" {
  description = "IAM role ARN the app must assume (via fromTokenFile) to read the DB secret"
  value       = aws_iam_role.db_secret_access.arn
}

output "db_security_group_id" {
  description = "Security group ID attached to the RDS instance"
  value       = aws_security_group.rds.id
}
