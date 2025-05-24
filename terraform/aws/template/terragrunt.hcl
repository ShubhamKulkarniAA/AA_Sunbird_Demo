generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
terraform {
  backend "s3" {
    bucket         = "${get_env("AWS_TERRAFORM_BACKEND_BUCKET")}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "${get_env("AWS_REGION")}"
    dynamodb_table = "${get_env("AWS_TERRAFORM_BACKEND_DYNAMODB_TABLE")}"
    encrypt        = true
  }
}
EOF
}

inputs = {
  aws_region           = "ap-south-1"
  vpc_cidr             = "10.10.0.0/16"
  public_subnet_cidr_1 = "10.10.1.0/24"
  public_subnet_cidr_2 = "10.10.2.0/24"
  availability_zone_1  = "ap-south-1a"
  availability_zone_2  = "ap-south-1b"

  eks_cluster_name     = "sunbirdedAA-demo-cluster"
  cluster_role_name    = "sunbirdedAA-demo-EKSClusterRole"
  node_role_name       = "sunbirdedAA-demo-EKSNodeRole"
  instance_type        = "t3.medium"
  desired_size         = 1
  max_size             = 1
  min_size             = 1


  s3_bucket_name       = "sunbirdedaa-demo-bucket"
  storage_account_name = "sunbirdedaa-demo-bucket"       # Use this same bucket name for your upload-files module
  storage_container_public = "public"   # your public container/folder in bucket
  environment          = "demo"
  s3_versioning_status = "Enabled"
}

# Add dependency blocks so terragrunt knows where the modules are:

dependency "vpc" {
  config_path = "./modules/vpc"
}

dependency "eks" {
  config_path = "./modules/eks"
}

dependency "keys" {
  # Adjust this relative path to where your keys module folder is
  config_path = "./keys"
}

dependency "upload_files" {
  # Adjust this relative path to where your upload-files module folder is
  config_path = "./upload-files"
}

dependency "output_file" {
  # Adjust this relative path to where your output-file module folder is
  config_path = "./output-file"
}
