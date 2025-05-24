# For local development
terraform {
  source = "../../modules//upload-files/"
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    s3_bucket_name = "dummy-bucket"
    s3_bucket_public_prefix = "dummy-public-prefix"
    s3_bucket_access_key = "dummy-access-key"
    s3_bucket_secret_key = "dummy-secret-key"
  }
}

inputs = {
  s3_bucket_name          = dependency.storage.outputs.s3_bucket_name
  s3_bucket_public_prefix = dependency.storage.outputs.s3_bucket_public_prefix
  s3_access_key           = dependency.storage.outputs.s3_bucket_access_key
  s3_secret_key           = dependency.storage.outputs.s3_bucket_secret_key
}
