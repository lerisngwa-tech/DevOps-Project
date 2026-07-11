aws_region  = "us-east-1"
project     = "myapp"
environment = "dev"

vpc_cidr             = "10.0.0.0/16"
azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnet_cidrs = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
public_subnet_cidrs  = ["10.0.48.0/24", "10.0.49.0/24", "10.0.50.0/24"]
single_nat_gateway   = true # cheaper for dev; set false in prod for one NAT per AZ

cluster_version = "1.30"

node_instance_types = ["t3.medium"]
node_capacity_type  = "ON_DEMAND"
node_min_size       = 1
node_max_size       = 3
node_desired_size   = 2

log_retention_days       = 14
ecr_untagged_expiry_days = 14

app_bucket_suffix                = "246312965731"
app_k8s_namespace                = "default"
app_s3_service_account_name      = "app-s3-access"
app_secrets_service_account_name = "app-secrets-access"

db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_max_allocated_storage = 50
db_multi_az              = false
db_deletion_protection   = false
db_skip_final_snapshot   = true

tags = {
  Team = "platform"
}
