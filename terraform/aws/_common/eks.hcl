locals {
  global_vars       = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment       = local.global_vars.global.environment
  building_block    = local.global_vars.global.building_block
  region            = local.global_vars.global.cloud_storage_region
  cluster_role_name = local.global_vars.global.eks.cluster_role_name
  node_role_name    = local.global_vars.global.eks.node_role_name
}

terraform {
  source = "../../modules//eks/"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    public_subnet_ids = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
  }
}

inputs = {
  eks_cluster_name  = "${local.environment}-${local.building_block}-eks"
  subnet_ids        = dependency.network.outputs.public_subnet_ids
  cluster_role_name = local.cluster_role_name
  node_role_name    = local.node_role_name
  instance_type     = "c5.4xlarge"
  desired_size      = 1
  max_size          = 2
  min_size          = 1
}
