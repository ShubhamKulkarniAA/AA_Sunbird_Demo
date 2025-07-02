locals {
  global_vars    = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment    = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
}

terraform {
  source = "../../modules//keys/"
}

dependency "storage" {
  config_path = "../storage" # Path to your storage module's Terragrunt HCL
  mock_outputs = {
    # UPDATED: mock outputs to match the new names from storage module's outputs.tf
    s3_bucket_name_public     = "dummy-bucket-public"    # Changed from aws_s3_bucket_name_public
    s3_bucket_name_private    = "dummy-bucket-private"   # Changed from aws_s3_bucket_name_private
    s3_bucket_arn_public      = "arn:aws:s3:::dummy-bucket-public" # Changed from aws_s3_bucket_arn_public
    s3_bucket_arn_private     = "arn:aws:s3:::dummy-bucket-private" # Changed from aws_s3_bucket_arn_private
    s3_bucket_dial_state      = "dummy-dial-state-bucket" # Changed from aws_s3_dial_state_bucket_name
    aws_kms_key_arn           = "arn:aws:kms:us-east-1:123456789012:key/dummy-key-id"
    s3_bucket_name            = "dummy-main-bucket" # Include main bucket if needed
  }
}

inputs = {
  environment         = local.environment
  building_block      = local.building_block
  aws_region          = local.global_vars.global.cloud_storage_region
  rsa_keys_count      = 2
  enable_terrahelp    = false

  # UPDATED: Get the S3 bucket names and KMS key ARN from the storage module's outputs
  s3_bucket_name_public  = dependency.storage.outputs.s3_bucket_name_public    # Changed from aws_s3_bucket_name_public
  s3_bucket_name_private = dependency.storage.outputs.s3_bucket_name_private   # Changed from aws_s3_bucket_name_private
  s3_bucket_arn_public   = dependency.storage.outputs.s3_bucket_arn_public     # Changed from aws_s3_bucket_arn_public
  s3_bucket_arn_private  = dependency.storage.outputs.s3_bucket_arn_private    # Changed from aws_s3_bucket_arn_private
  kms_key_arn            = dependency.storage.outputs.aws_kms_key_arn
}
