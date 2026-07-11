variable "project" {
  description = "Project name, used in the log group path"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster, used for the Container Insights log group name"
  type        = string
}

variable "retention_days" {
  description = "CloudWatch log retention in days for application log groups"
  type        = number
  default     = 30
}

variable "enable_container_insights" {
  description = "Whether to create the Container Insights application log group"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to the log groups"
  type        = map(string)
  default     = {}
}
