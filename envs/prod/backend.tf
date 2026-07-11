terraform {
  backend "s3" {
    bucket         = "changeme-terraform-state-us-east-1" # must match bootstrap's state_bucket_name output
    key            = "envs/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks" # must match bootstrap's lock_table_name output
    encrypt        = true
  }
}
