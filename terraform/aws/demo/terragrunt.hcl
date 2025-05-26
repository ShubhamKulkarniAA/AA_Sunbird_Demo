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
  # Please verify this: should be an AZ name like "ap-south-1b", not a CIDR
  availability_zone_2        = "ap-south-1b"

  eks_cluster_name           = "demo-sunbirdedAA-eks"
  cluster_role_name          = "sunbirdedAA-demo-EKSClusterRole"
  node_role_name             = "sunbirdedAA-demo-EKSNodeRole"
  instance_type              = "c5.4xlarge"
  disk_size                  = 500 # Increase to 500GiB or more
  desired_size               = 4
  max_size                   = 5
  min_size                   = 3

  # --- MODIFIED: Enable AWS EBS CSI Driver ---
  # Changed variable name to match the module's new variable (enable_ebs_csi_driver)
  enable_ebs_csi_driver = true
  # ----------------------------------------

  bucket_name                = "sunbirdedaa-demo-bucket"
  storage_account_name       = "sunbirdedaa-demo-bucket"
  schemas_path               = "../modules/upload-files/schemas"
}
