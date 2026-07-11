aws_region  = "us-east-1"
project     = "myapp"
environment = "stg"

vpc_cidr             = "10.1.0.0/16"
azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs = ["10.1.0.0/20", "10.1.16.0/20", "10.1.32.0/20"]
public_subnet_cidrs  = ["10.1.48.0/24", "10.1.49.0/24", "10.1.50.0/24"]
single_nat_gateway   = true # cheaper for staging; set false in prod for one NAT per AZ

cluster_version = "1.30"

node_instance_types = ["t3.medium"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 2
node_max_size       = 4
node_desired_size   = 2

log_retention_days       = 30
ecr_untagged_expiry_days = 14

app_bucket_suffix                = "changeme-account-id"
app_k8s_namespace                = "myapp-stg"
app_s3_service_account_name      = "app-s3-access"
app_secrets_service_account_name = "app-secrets-access"

db_instance_class        = "db.t4g.small"
db_allocated_storage     = 20
db_max_allocated_storage = 100
db_multi_az              = false
db_deletion_protection   = true
db_skip_final_snapshot   = false

tags = {
  Team = "platform"
}
