variable "aws_region" {}
variable "base_location" {}
variable "rsa_keys_count" {}
variable "bucket_name" {}
variable "environment" {}
variable "enable_terrahelp" {
  description = "Whether to enable terrahelp encryption"
  type        = bool
  default     = false
}
