variable "project" {
  description = "Project name, used as a resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "bucket_suffix" {
  description = "Suffix appended to the bucket name to help ensure global uniqueness (e.g. account ID or random string)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's OIDC provider (from the eks module output)"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS cluster's OIDC provider, without the https:// prefix (e.g. oidc.eks.us-east-1.amazonaws.com/id/XXXX)"
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
  default     = "app-s3-access"
}

variable "tags" {
  description = "Common tags applied to the app S3 bucket and IAM role"
  type        = map(string)
  default     = {}
}
