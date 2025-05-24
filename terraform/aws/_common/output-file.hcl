locals {
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  env             = local.global_vars.global.env
  environment     = local.global_vars.global.environment
  building_block  = local.global_vars.global.building_block
  aws_region      = local.global_vars.global.cloud_storage_region
}

terraform {
  source = "../../modules//output-file/"
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    s3_bucket_name_public     = "dummy-bucket-public"
    s3_bucket_name_private    = "dummy-bucket-private"
    s3_bucket_arn_public      = "arn:aws:s3:::dummy-bucket-public"
    s3_bucket_dial_state      = "dummy-dial-state-bucket"
  }
}

dependency "eks" {
  config_path = "../eks"
}

dependency "keys" {
  config_path = "../keys"
  mock_outputs = {
    random_string     = "dummy-string"
    encryption_string = "dummy-encryption-key"
  }
}

inputs = {
  env                         = local.env
  environment                 = local.environment
  building_block              = local.building_block
  aws_region                  = local.aws_region

  private_ingressgateway_ip   = dependency.eks.outputs.private_ingressgateway_ip

  s3_bucket_name_public       = dependency.storage.outputs.s3_bucket_name_public
  s3_bucket_name_private      = dependency.storage.outputs.s3_bucket_name_private
  s3_bucket_arn_public        = dependency.storage.outputs.s3_bucket_arn_public
  dial_state_bucket           = dependency.storage.outputs.s3_bucket_dial_state

  encryption_string           = dependency.keys.outputs.encryption_string
  random_string               = dependency.keys.outputs.random_string
}
