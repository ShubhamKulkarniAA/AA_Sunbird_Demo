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
