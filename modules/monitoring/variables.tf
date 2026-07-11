variable "chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "62.7.0"
}

variable "grafana_storage_size" {
  description = "Size of the persistent volume for Grafana"
  type        = string
  default     = "2Gi"
}

variable "prometheus_storage_size" {
  description = "Size of the persistent volume for Prometheus"
  type        = string
  default     = "10Gi"
}

variable "cluster_name" {
  description = "Name of the EKS cluster, used to name the Grafana CloudWatch IRSA role"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the CloudWatch datasource"
  type        = string
  default     = "us-east-1"
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's OIDC provider (from the eks module output)"
  type        = string
}
