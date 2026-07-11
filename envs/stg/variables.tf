variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a resource name prefix"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (must be 3 for multi-AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT gateway instead of one per AZ"
  type        = bool
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "node_instance_types" {
  description = "Instance types for the EKS managed node group"
  type        = list(string)
}

variable "node_capacity_type" {
  description = "Capacity type for the node group: ON_DEMAND or SPOT"
  type        = string
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group's ASG"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group's ASG"
  type        = number
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group's ASG"
  type        = number
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
}

variable "ecr_untagged_expiry_days" {
  description = "Days before untagged ECR images expire"
  type        = number
}

variable "app_bucket_suffix" {
  description = "Suffix appended to the app S3 bucket name for global uniqueness (e.g. your AWS account ID)"
  type        = string
}

variable "app_k8s_namespace" {
  description = "Kubernetes namespace the application is deployed into"
  type        = string
}

variable "app_s3_service_account_name" {
  description = "Kubernetes ServiceAccount name annotated for S3 bucket access via IRSA"
  type        = string
}

variable "app_secrets_service_account_name" {
  description = "Kubernetes ServiceAccount name annotated for Secrets Manager access via IRSA"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "db_allocated_storage" {
  description = "Initial RDS allocated storage in GB"
  type        = number
}

variable "db_max_allocated_storage" {
  description = "RDS storage autoscaling ceiling in GB"
  type        = number
}

variable "db_multi_az" {
  description = "Whether to deploy a Multi-AZ RDS standby replica"
  type        = bool
}

variable "db_deletion_protection" {
  description = "Whether to enable RDS deletion protection"
  type        = bool
}

variable "db_skip_final_snapshot" {
  description = "Whether to skip the final RDS snapshot on destroy"
  type        = bool
}

variable "tags" {
  description = "Additional common tags applied to all resources"
  type        = map(string)
  default     = {}
}
