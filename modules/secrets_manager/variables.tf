variable "project" {
  description = "Project name, used as a resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "recovery_window_in_days" {
  description = "Number of days AWS waits before permanently deleting the secret after a destroy"
  type        = number
  default     = 7
}

variable "initial_secret_value" {
  description = "Initial placeholder key/value map stored in the secret; update via console/CLI afterwards (changes are ignored by Terraform)"
  type        = map(string)
  default     = { placeholder = "changeme" }
  sensitive   = true
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
  description = "Kubernetes ServiceAccount name that will be annotated with this role's ARN"
  type        = string
  default     = "app-secrets-access"
}

variable "tags" {
  description = "Common tags applied to the secret and IAM role"
  type        = map(string)
  default     = {}
}
