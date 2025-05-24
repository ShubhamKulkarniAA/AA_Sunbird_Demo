variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket to upload files to."
}

variable "schemas_path" {
  type        = string
  description = "Local path to schema JSON templates."
}
