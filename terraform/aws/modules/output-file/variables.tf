variable "env" {
  type        = string
  description = "Environment short name. Used as a prefix in Helm charts and other resources."
}

variable "environment" {
  type        = string
  description = "Full environment name. Used as a prefix in Terraform resources."
}

variable "building_block" {
  type        = string
  description = "Building block name to prefix resources."
}

variable "aws_access_key_id" {
  description = "AWS access key ID"
  type        = string
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
  type        = string
}

variable "bucket_name" {
  type        = string
  description = "AWS S3 bucket name where the global cloud values YAML file will be uploaded."
}

variable "s3_private_path" {
  type        = string
  description = "S3 path for private data storage (can be used in template file)."
  default     = ""
}

variable "s3_public_path" {
  type        = string
  description = "S3 path for public data storage (can be used in template file)."
  default     = ""
}

variable "s3_dial_state_path" {
  type        = string
  description = "S3 path for dial state data storage (can be used in template file)."
  default     = ""
}

variable "private_ingressgateway_ip" {
  type        = string
  description = "Private Load Balancer IP address."
  default     = ""
}

variable "encryption_string" {
  type        = string
  description = "Encryption string to encrypt/mask various values. Must be exactly 32 characters long."
  validation {
    condition     = length(var.encryption_string) == 32
    error_message = "The encryption string must be exactly 32 characters in length."
  }
}

variable "random_string" {
  type        = string
  description = "Random string used for encrypting/masking values. Length should be between 12 and 24 characters."
  validation {
    condition     = length(var.random_string) >= 12 && length(var.random_string) <= 24
    error_message = "The random string must have a length between 12 and 24 characters."
  }
}

variable "base_location" {
  type        = string
  description = "Location of the Terraform execution folder."
}

variable "aws_region" {
  type        = string
  description = "AWS region where the S3 bucket is located."
}
