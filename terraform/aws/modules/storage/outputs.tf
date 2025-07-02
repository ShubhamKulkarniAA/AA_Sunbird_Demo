output "s3_bucket_name" {
  description = "The name of the S3 bucket created by this module."
  value       = aws_s3_bucket.my_bucket.id
}

output "s3_bucket_name_public" { 
  description = "The name of the public S3 bucket."
  value       = aws_s3_bucket.public_bucket.id
}

output "s3_bucket_arn_public" {
  description = "The ARN of the public S3 bucket."
  value       = aws_s3_bucket.public_bucket.arn
}

output "s3_bucket_name_private" { 
  description = "The name of the private S3 bucket."
  value       = aws_s3_bucket.private_bucket.id
}

output "s3_bucket_arn_private" {
  description = "The ARN of the private S3 bucket."
  value       = aws_s3_bucket.private_bucket.arn
}

output "s3_bucket_dial_state" { 
  description = "The name of the Dial state S3 bucket."
  value       = aws_s3_bucket.dial_state_bucket.id
}

output "aws_kms_key_arn" {
  description = "The ARN of the KMS key for S3 encryption."
  value       = var.create_kms_key ? aws_kms_key.s3_key[0].arn : null
}
