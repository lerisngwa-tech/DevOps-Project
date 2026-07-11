variable "project" {
  description = "Project name, used as a resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prod)"
  type        = string
}

variable "untagged_expiry_days" {
  description = "Number of days after which untagged images are expired from the repository"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Common tags applied to the ECR repository"
  type        = map(string)
  default     = {}
}
