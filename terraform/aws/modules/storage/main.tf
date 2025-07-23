
resource "aws_s3_bucket" "my_bucket" {
  bucket = var.bucket_name
  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = var.versioning_status
  }
}

resource "aws_s3_bucket_public_access_block" "my_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.my_bucket.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# --- Public Bucket ---
resource "aws_s3_bucket" "public_bucket" {
  bucket = var.aws_s3_public_bucket_name
  tags = {
    Environment = var.environment
    Name        = "sunbird-public-bucket"
  }
}

# REMOVED: resource "aws_s3_bucket_acl" "public_bucket_acl"
# Replaced with a bucket policy for public read access.
resource "aws_s3_bucket_policy" "public_bucket_policy" {
  bucket = aws_s3_bucket.public_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.public_bucket.arn}/*"
      },
    ],
  })
}

resource "aws_s3_bucket_public_access_block" "public_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.public_bucket.id
  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

# --- Private Bucket ---
resource "aws_s3_bucket" "private_bucket" {
  bucket = var.aws_s3_private_bucket_name
  tags = {
    Environment = var.environment
    Name        = "sunbird-private-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "private_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.private_bucket.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# --- Dial State Bucket ---
resource "aws_s3_bucket" "dial_state_bucket" {
  bucket = var.aws_s3_dial_state_bucket_name
  tags = {
    Environment = var.environment
    Name        = "sunbird-dial-state-bucket"
  }
}

# --- KMS Key for S3 Encryption ---
resource "aws_kms_key" "s3_key" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Enable IAM User Permissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "Allow S3 to use KMS key"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "s3_key_alias" {
  count         = var.create_kms_key ? 1 : 0
  name          = var.kms_key_alias
  target_key_id = aws_kms_key.s3_key[0].id
}

data "aws_caller_identity" "current" {}
