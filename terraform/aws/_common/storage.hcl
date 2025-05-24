locals {
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment     = local.global_vars.global.environment
  building_block  = local.global_vars.global.building_block
  aws_region      = local.global_vars.global.cloud_storage_region
  bucket_name     = local.global_vars.global.s3.bucket_name
  versioning_status = local.global_vars.global.s3.versioning_status

}

terraform {
  source = "../../modules//storage/"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    vpc_id             = "dummy-vpc-id"
    public_subnet_ids  = ["subnet-abc123", "subnet-def456"]
  }
}

inputs = {
  environment        = local.environment
  building_block     = local.building_block
  aws_region         = local.aws_region
  bucket_name        = local.bucket_name
  versioning_status  = local.versioning_status
  vpc_id             = dependency.network.outputs.vpc_id
  public_subnet_ids  = dependency.network.outputs.public_subnet_ids
}
