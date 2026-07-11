variable "project" {
  description = "Project name, used as a resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the RDS instance will run"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Security group ID of the EKS worker nodes (module.eks.node_security_group_id) — the only source allowed to reach RDS"
  type        = string
}

variable "engine_version" {
  description = "Postgres engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GB"
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "Whether to deploy a Multi-AZ standby replica"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the DB instance"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot on destroy (convenient for dev only)"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Name of the initial database created on the instance"
  type        = string
  default     = "tasktracker"
}

variable "master_username" {
  description = "Master username for the DB instance"
  type        = string
  default     = "app_admin"
}

variable "recovery_window_in_days" {
  description = "Number of days AWS waits before permanently deleting the DB secret after a destroy"
  type        = number
  default     = 7
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's OIDC provider (from the eks module output)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS cluster's OIDC provider, without the https:// prefix"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace of the ServiceAccount that will assume this role"
  type        = string
  default     = "default"
}

variable "k8s_service_account_name" {
  description = "Kubernetes ServiceAccount name trusted to assume this role"
  type        = string
  default     = "app-s3-access"
}

variable "tags" {
  description = "Common tags applied to all RDS resources"
  type        = map(string)
  default     = {}
}
