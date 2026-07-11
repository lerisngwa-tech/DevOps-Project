aws_region  = "us-east-1"
project     = "myapp"
environment = "prod"

vpc_cidr             = "10.2.0.0/16"
azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs = ["10.2.0.0/20", "10.2.16.0/20", "10.2.32.0/20"]
public_subnet_cidrs  = ["10.2.48.0/24", "10.2.49.0/24", "10.2.50.0/24"]
single_nat_gateway   = false # one NAT gateway per AZ for production resilience

cluster_version = "1.30"

node_instance_types = ["t3.large"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 3
node_max_size       = 6
node_desired_size   = 3

log_retention_days       = 90
ecr_untagged_expiry_days = 30

app_bucket_suffix                = "changeme-account-id"
app_k8s_namespace                = "default"
app_s3_service_account_name      = "app-s3-access"
app_secrets_service_account_name = "app-secrets-access"

db_instance_class        = "db.t4g.medium"
db_allocated_storage     = 50
db_max_allocated_storage = 200
db_multi_az              = true
db_deletion_protection   = true
db_skip_final_snapshot   = false

tags = {
  Team = "platform"
}
