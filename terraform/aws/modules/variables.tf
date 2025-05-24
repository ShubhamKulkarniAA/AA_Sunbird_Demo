variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidr_1" {
  description = "CIDR block for the first public subnet"
  type        = string
}

variable "public_subnet_cidr_2" {
  description = "CIDR block for the second public subnet"
  type        = string
}

variable "availability_zone_1" {
  description = "First availability zone"
  type        = string
}

variable "availability_zone_2" {
  description = "Second availability zone"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS worker nodes"
  type        = list(string)
  default     = []
}

variable "cluster_role_name" {
  description = "IAM role name for EKS cluster"
  type        = string
}

variable "node_role_name" {
  description = "IAM role name for EKS nodes"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
}

variable "desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
}

variable "min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "environment" {
  description = "Environment (e.g. dev, staging, prod)"
  type        = string
}

variable "s3_versioning_status" {
  description = "S3 versioning status (Enabled or Suspended)"
  type        = string
}
