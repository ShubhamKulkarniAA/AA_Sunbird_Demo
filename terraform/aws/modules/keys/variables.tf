variable "environment" {
  type        = string
  description = "Environment name. Used as a prefix for resources."
}

variable "building_block" {
  type        = string
  description = "Building block name. Used as a prefix for resources."
}

variable "s3_bucket_name" {
  type        = string
  description = "The name of the S3 bucket to upload files to."
}

variable "aws_region" {
  type        = string
  description = "AWS region for S3 operations."
}

variable "base_location" {
  type        = string
  description = "Location of Terraform execution folder."
}

variable "rsa_keys_count" {
  type        = number
  description = "Number of RSA keys to generate."
  default     = 2
}
