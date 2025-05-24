locals {
  global_vars    = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  bucket_name    = local.global_vars.global.s3.bucket_name
  # Assuming your schemas directory is relative to this config file
  schemas_path   = "${get_terragrunt_dir()}/schemas"
}

terraform {
  source = "../../modules//upload-files/"
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    bucket_name = "dummy-bucket"
  }
}

inputs = {
  bucket_name  = local.bucket_name
  schemas_path = local.schemas_path
}
