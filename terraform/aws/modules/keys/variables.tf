variable "aws_region" {
  type        = string
  description = "AWS region for resources."
}
variable "base_location" {
  type        = string
  description = "Base location for key storage, if applicable."
  default     = "keys"
}
variable "rsa_keys_count" {
  type        = number
  description = "Number of RSA keys to generate."
  default     = 2
}
variable "environment" {
  type        = string
  description = "The deployment environment (e.g., dev, prod)."
}
variable "enable_terrahelp" {
  description = "Whether to enable terrahelp encryption"
  type        = bool
  default     = false
}

# New variables for S3 buckets and KMS key that are inputs to the keys module

variable "bucket_name" {
  description = "Name of the S3 bucket where values will be uploaded."
  type        = string
}

variable "s3_bucket_name_public" {
  type        = string
  description = "Name of the public S3 bucket for keys."
}
variable "s3_bucket_name_private" {
  type        = string
  description = "Name of the private S3 bucket for keys."
}
variable "s3_bucket_arn_public" {
  type        = string
  description = "ARN of the public S3 bucket for keys."
}
variable "s3_bucket_arn_private" {
  type        = string
  description = "ARN of the private S3 bucket for keys."
}
variable "kms_key_arn" {
  type        = string
  description = "ARN of the KMS key for encryption."
}
