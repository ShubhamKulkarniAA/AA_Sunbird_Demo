# VPC
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidr_1 = "10.0.1.0/24"
public_subnet_cidr_2 = "10.0.2.0/24"
availability_zone_1  = "ap-south-1a"
availability_zone_2  = "ap-south-1b"

# EKS
eks_cluster_name  = "sunbirdedAA-demo-cluster"
cluster_role_name = "sunbirdedAA-demo-EKSClusterRole" # prefixed for clarity
node_role_name    = "sunbirdedAA-demo-EKSNodeRole"    # prefixed for clarity
instance_type     = "t3.medium"
desired_size      = 1
max_size          = 1
min_size          = 1

# S3
s3_bucket_name       = "sunbirdedaa-demo-bucket"
environment          = "demo"
s3_versioning_status = "Enabled"
