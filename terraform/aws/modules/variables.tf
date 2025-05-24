variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr_1" {
  description = "CIDR block for the first public subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "public_subnet_cidr_2" {
  description = "CIDR block for the second public subnet"
  type        = string
  default     = "10.10.2.0/24"
}

variable "availability_zone_1" {
  description = "First availability zone"
  type        = string
  default     = "ap-south-1a"
}

variable "availability_zone_2" {
  description = "Second availability zone"
  type        = string
  default     = "ap-south-1b"
}

variable "eks_cluster_name" {
  description = "EKS Cluster Name"
  type        = string
  default     = "sunbirdedAA-demo-cluster"
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS worker nodes"
  type        = list(string)
  default     = []
}

variable "cluster_role_name" {
  description = "IAM role name for EKS cluster"
  type        = string
  default     = "sunbirdedAA-demo-EKSClusterRole"
}

variable "node_role_name" {
  description = "IAM role name for EKS nodes"
  type        = string
  default     = "sunbirdedAA-demo-EKSNodeRole"
}

variable "instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
  default     = "sunbirdedaa-demo-bucket"
}

variable "environment" {
  description = "Environment (e.g. dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "s3_versioning_status" {
  description = "S3 versioning status (Enabled or Suspended)"
  type        = string
  default     = "Enabled"
}
