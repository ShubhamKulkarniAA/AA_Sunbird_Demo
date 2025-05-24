locals {
  # This section will be enabled after final code is pushed and tagged
  # source_base_url = "github.com/<org>/modules.git//app"
  global_vars    = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment    = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  # random_string = local.environment_vars.locals.random_string
}

terraform {
  source = "../../modules//keys/"
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    aws_s3_bucket_name_public  = "dummy-bucket-public"
    aws_s3_bucket_name_private = "dummy-bucket-private"
    aws_s3_bucket_arn_public   = "arn:aws:s3:::dummy-bucket-public"
    aws_s3_bucket_arn_private  = "arn:aws:s3:::dummy-bucket-private"
    aws_kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/dummy-key-id"
  }
}

inputs = {
  environment               = local.environment
  building_block            = local.building_block
  s3_bucket_name_public     = dependency.storage.outputs.aws_s3_bucket_name_public
  s3_bucket_name_private    = dependency.storage.outputs.aws_s3_bucket_name_private
  s3_bucket_arn_public      = dependency.storage.outputs.aws_s3_bucket_arn_public
  s3_bucket_arn_private     = dependency.storage.outputs.aws_s3_bucket_arn_private
  kms_key_arn               = dependency.storage.outputs.aws_kms_key_arn
  # random_string           = local.random_string
}
