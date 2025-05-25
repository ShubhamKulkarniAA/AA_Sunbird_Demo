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
  aws_region                 = "ap-south-1"
  vpc_cidr                   = "10.10.0.0/16"
  public_subnet_cidr_1       = "10.10.1.0/24"
  public_subnet_cidr_2       = "10.10.2.0/24"
  availability_zone_1        = "ap-south-1a"
  availability_zone_2        = "ap-south-1b"

  eks_cluster_name           = "demo-sunbirdedAA-eks"
  cluster_role_name          = "sunbirdedAA-demo-EKSClusterRole"
  node_role_name             = "sunbirdedAA-demo-EKSNodeRole"
  instance_type              = "t3.medium"
  desired_size               = 1
  max_size                   = 1
  min_size                   = 1

  bucket_name                = "sunbirdedaa-demo-bucket"
  storage_account_name       = "sunbirdedaa-demo-bucket"
  schemas_path               = "../modules/upload-files/schemas"
  storage_container_public   = "public"
  environment                = "demo"
  s3_versioning_status       = "Enabled"

  rsa_keys_count             = 2
  aws_s3_public_bucket_name  = "sunbirdedaa-demo-public-bucket"
  aws_s3_private_bucket_name = "sunbirdedaa-demo-private-bucket"
  aws_s3_dial_state_bucket_name = "sunbirdedaa-demo-dialstate-bucket"
}

include "network" {
  path = "${get_original_terragrunt_dir()}/../_common/network.hcl"
  inputs = {
    aws_region = var.aws_region
    vpc_cidr_block = var.vpc_cidr
    public_subnet_cidr_1 = var.public_subnet_cidr_1
    public_subnet_cidr_2 = var.public_subnet_cidr_2
    availability_zone_1 = var.availability_zone_1
    availability_zone_2 = var.availability_zone_2
  }
}

include "eks" {
  path = "${get_original_terragrunt_dir()}/../_common/eks.hcl"
  dependencies {
    paths = ["${get_original_terragrunt_dir()}/network"]
  }
  inputs = {
    eks_cluster_name = var.eks_cluster_name
    cluster_role_name = var.cluster_role_name
    node_role_name = var.node_role_name
    instance_type = var.instance_type
    desired_size = var.desired_size
    max_size = var.max_size
    min_size = var.min_size
    # These depend on network module outputs
    vpc_id = include.network.outputs.vpc_id
    public_subnet_ids = include.network.outputs.public_subnet_ids
    private_subnet_ids = include.network.outputs.private_subnet_ids
  }
}

include "storage" {
  path = "${get_original_terragrunt_dir()}/../_common/storage.hcl"
  dependencies {
    paths = ["${get_original_terragrunt_dir()}/network"]
  }
  inputs = {
    aws_region = var.aws_region
    bucket_name = var.bucket_name
    versioning_status = var.s3_versioning_status
    aws_s3_public_bucket_name = var.aws_s3_public_bucket_name
    aws_s3_private_bucket_name = var.aws_s3_private_bucket_name
    aws_s3_dial_state_bucket_name = var.aws_s3_dial_state_bucket_name
    # These depend on network module outputs
    vpc_id = include.network.outputs.vpc_id
    public_subnet_ids = include.network.outputs.public_subnet_ids
  }
}

include "keys" {
  path = "${get_original_terragrunt_dir()}/../_common/keys.hcl"
  dependencies {
    paths = ["${get_original_terragrunt_dir()}/storage"]
  }
  inputs = {
    rsa_keys_count = var.rsa_keys_count
    # These depend on storage module outputs
    s3_bucket_name_public = include.storage.outputs.aws_s3_bucket_name_public
    s3_bucket_name_private = include.storage.outputs.aws_s3_bucket_name_private
    s3_bucket_arn_public = include.storage.outputs.aws_s3_bucket_arn_public
    s3_bucket_arn_private = include.storage.outputs.aws_s3_bucket_arn_private
    kms_key_arn = include.storage.outputs.aws_kms_key_arn
  }
}

include "output-file" {
  path = "${get_original_terragrunt_dir()}/../_common/output-file.hcl"
  dependencies {
    paths = [
      "${get_original_terragrunt_dir()}/storage",
      "${get_original_terragrunt_dir()}/eks",
      "${get_original_terragrunt_dir()}/keys"
    ]
  }
  inputs = {
    environment = var.environment
    aws_region = var.aws_region
    # These depend on storage module outputs
    s3_bucket_name_public = include.storage.outputs.aws_s3_bucket_name_public
    s3_bucket_name_private = include.storage.outputs.aws_s3_bucket_name_private
    s3_bucket_arn_public = include.storage.outputs.aws_s3_bucket_arn_public
    dial_state_bucket = include.storage.outputs.s3_bucket_dial_state
    # These depend on keys module outputs
    encryption_string = include.keys.outputs.encryption_string
    random_string = include.keys.outputs.random_string
  }
}

include "upload-files" {
  path = "${get_original_terragrunt_dir()}/../_common/upload-files.hcl"
  dependencies {
    paths = ["${get_original_terragrunt_dir()}/storage"]
  }
  inputs = {
    # This depends on storage module output
    bucket_name = include.storage.outputs.bucket_name
    schemas_path = var.schemas_path
  }
}

output "eks_cluster_name" {
  value       = include.eks.outputs.eks_cluster_name
  description = "The name of the EKS cluster deployed."
}

output "vpc_id" {
  value       = include.network.outputs.vpc_id
  description = "The ID of the VPC created by the network module."
}

output "public_subnet_ids" {
  value       = include.network.outputs.public_subnet_ids
  description = "The IDs of the public subnets created by the network module."
}

output "private_subnet_ids" {
  value       = include.network.outputs.private_subnet_ids
  description = "The IDs of the private subnets created by the network module."
}
