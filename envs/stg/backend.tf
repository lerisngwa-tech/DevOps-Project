terraform {
  backend "s3" {
    bucket         = "myapp-tfstate-246312965731" # must match bootstrap's state_bucket_name output
    key            = "envs/stg/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks" # must match bootstrap's lock_table_name output
    encrypt        = true
  }
}
