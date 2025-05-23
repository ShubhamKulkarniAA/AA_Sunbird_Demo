module "vpc" {
  source = "./network"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr_1 = var.public_subnet_cidr_1
  public_subnet_cidr_2 = var.public_subnet_cidr_2
  availability_zone_1  = var.availability_zone_1
  availability_zone_2  = var.availability_zone_2
}

module "eks" {
  source = "./eks"

  eks_cluster_name  = var.eks_cluster_name
  subnet_ids        = module.vpc.public_subnet_ids
  cluster_role_name = var.cluster_role_name
  node_role_name    = var.node_role_name
  instance_type     = var.instance_type
  desired_size      = var.desired_size
  max_size          = var.max_size
  min_size          = var.min_size
}

module "s3_bucket" {
  source = "./storage"

  bucket_name       = var.s3_bucket_name
  environment       = var.environment
  versioning_status = var.s3_versioning_status
}
