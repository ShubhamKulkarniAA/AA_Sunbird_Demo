variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket"
}

variable "environment" {
  type        = string
  description = "The environment the bucket belongs to (e.g., dev, staging, prod)"
}

variable "versioning_status" {
  type        = string
  description = "The versioning status of the bucket (Enabled or Disabled)"
  default     = "Disabled"
}

# --- New Variables ---
variable "aws_s3_public_bucket_name" {
  type        = string
  description = "The name for the public S3 bucket."
}

variable "aws_s3_private_bucket_name" {
  type        = string
  description = "The name for the private S3 bucket."
}

variable "aws_s3_dial_state_bucket_name" {
  type        = string
  description = "The name for the Dial state S3 bucket."
}

variable "create_kms_key" {
  type        = bool
  description = "Set to true to create a KMS key for S3 encryption, false otherwise."
  default     = true
}

variable "kms_key_alias" {
  type        = string
  description = "The alias for the KMS key."
  default     = "alias/sunbird-s3-key"
}
