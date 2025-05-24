locals {
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment     = local.global_vars.global.environment
  building_block  = local.global_vars.global.building_block
  aws_region      = local.global_vars.global.cloud_storage_region

  vpc_cidr_block  = local.global_vars.global.vpc.cidr_block
  azs = [
    local.global_vars.global.vpc.availability_zone_1,
    local.global_vars.global.vpc.availability_zone_2
  ]
}

terraform {
  source = "../../modules//network/"
}

inputs = {
  environment        = local.environment
  building_block     = local.building_block
  region             = local.aws_region
  vpc_cidr_block     = local.vpc_cidr_block
  availability_zones = local.azs
}
