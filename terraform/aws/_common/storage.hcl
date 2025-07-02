locals {
  global_vars       = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment       = local.global_vars.global.environment
  building_block    = local.global_vars.global.building_block
  aws_region        = local.global_vars.global.cloud_storage_region
  bucket_name       = local.global_vars.global.s3.bucket_name
  versioning_status = local.global_vars.global.s3.versioning_status

  # These values are expected to be in your global-values.yaml for consistency
  public_bucket_name     = local.global_vars.global.s3.public_bucket_name
  private_bucket_name    = local.global_vars.global.s3.private_bucket_name
  dial_state_bucket_name = local.global_vars.global.s3.dial_state_bucket_name
  create_kms_key         = lookup(local.global_vars.global.kms, "create_key", true)
  kms_key_alias          = lookup(local.global_vars.global.kms, "key_alias", "alias/sunbird-s3-key")
}

terraform {
  source = "../../modules//storage/"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    vpc_id           = "dummy-vpc-id"
    public_subnet_ids = ["subnet-abc123", "subnet-def456"]
  }
}

inputs = {
  environment                 = local.environment
  building_block              = local.building_block
  aws_region                  = local.aws_region
  bucket_name                 = local.bucket_name
  versioning_status           = local.versioning_status
  vpc_id                      = dependency.network.outputs.vpc_id
  public_subnet_ids           = dependency.network.outputs.public_subnet_ids

  # Pass new bucket names and KMS config to the storage module
  aws_s3_public_bucket_name   = local.public_bucket_name
  aws_s3_private_bucket_name  = local.private_bucket_name
  aws_s3_dial_state_bucket_name = local.dial_state_bucket_name
  create_kms_key              = local.create_kms_key
  kms_key_alias               = local.kms_key_alias
}
