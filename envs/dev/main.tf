locals {
  cluster_name = "${var.project}-${var.environment}"

  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

module "vpc" {
  source = "../../modules/vpc"

  project      = var.project
  environment  = var.environment
  cluster_name = local.cluster_name

  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway

  tags = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  environment     = var.environment
  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size

  log_retention_days = var.log_retention_days

  tags = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  untagged_expiry_days = var.ecr_untagged_expiry_days

  tags = local.common_tags
}

module "s3_app_bucket" {
  source = "../../modules/s3_app_bucket"

  project     = var.project
  environment = var.environment

  bucket_suffix = var.app_bucket_suffix

  oidc_provider_arn        = module.eks.oidc_provider_arn
  oidc_provider_url        = module.eks.oidc_provider_url
  k8s_namespace            = var.app_k8s_namespace
  k8s_service_account_name = var.app_s3_service_account_name

  tags = local.common_tags
}

module "secrets_manager" {
  source = "../../modules/secrets_manager"

  project     = var.project
  environment = var.environment

  oidc_provider_arn        = module.eks.oidc_provider_arn
  oidc_provider_url        = module.eks.oidc_provider_url
  k8s_namespace            = var.app_k8s_namespace
  k8s_service_account_name = var.app_secrets_service_account_name

  tags = local.common_tags
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project      = var.project
  environment  = var.environment
  cluster_name = local.cluster_name

  retention_days = var.log_retention_days

  tags = local.common_tags
}

module "alb_controller" {
  source = "../../modules/alb_controller"

  cluster_name = local.cluster_name
  aws_region   = var.aws_region
  vpc_id       = module.vpc.vpc_id

  oidc_provider_arn = module.eks.oidc_provider_arn

  tags = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  cluster_name      = local.cluster_name
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Needs the AWS Load Balancer Controller already running to provision the
  # NLB behind Grafana's Service annotations.
  depends_on = [module.alb_controller]
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  eks_node_security_group_id = module.eks.node_security_group_id

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  multi_az              = var.db_multi_az
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot

  oidc_provider_arn        = module.eks.oidc_provider_arn
  oidc_provider_url        = module.eks.oidc_provider_url
  k8s_namespace            = var.app_k8s_namespace
  k8s_service_account_name = var.app_s3_service_account_name

  tags = local.common_tags
}
