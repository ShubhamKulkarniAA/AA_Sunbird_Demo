include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "common" {
  path = "${get_terragrunt_dir()}/../_common/output-file.hcl"
}

inputs = {
  aws_access_key_id             = get_env("AWS_ACCESS_KEY_ID")
  aws_secret_access_key         = get_env("AWS_SECRET_ACCESS_KEY")
  aws_region                    = get_env("AWS_REGION")

  env                           = "demo"
  environment                   = "demo-env"
  building_block                = "nervecenter"

  encryption_string             = "12345678901234567890123456789012"
  random_string                 = "someRandomStr1234"

  aws_s3_public_bucket_name     = "sunbirdedaa-demo-public-bucket"
  aws_s3_private_bucket_name    = "sunbirdedaa-demo-private-bucket"
  aws_s3_dial_state_bucket_name = "sunbirdedaa-demo-dialstate-bucket"

  private_ingressgateway_ip     = "1.2.3.4"
}
