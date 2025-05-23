#VPC Variables
variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidr_1" {
  type = string
}

variable "public_subnet_cidr_2" {
  type = string
}

variable "availability_zone_1" {
  type = string
}

variable "availability_zone_2" {
  type = string
}

#EKS Variables
variable "eks_cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "cluster_role_name" {
  type        = string
  description = "Name of the IAM role for the EKS cluster"
}

variable "node_role_name" {
  type        = string
  description = "Name of the IAM role for the EKS worker nodes"
}

variable "instance_type" {
  type        = string
  description = "Instance type for the EKS worker nodes"
}

variable "desired_size" {
  type        = number
  description = "Desired number of worker nodes"
}

variable "max_size" {
  type        = number
  description = "Maximum number of worker nodes"
}

variable "min_size" {
  type        = number
  description = "Minimum number of worker nodes"
}

#S3 Variables
variable "s3_bucket_name" {
  type        = string
  description = "The name of the S3 bucket"
}

variable "environment" {
  type        = string
  description = "The environment the bucket belongs to (e.g., dev, staging, prod)"
  default     = "default"
}

variable "s3_versioning_status" {
  type        = string
  description = "The versioning status of the S3 bucket (Enabled or Disabled)"
  default     = "Disabled"
}
