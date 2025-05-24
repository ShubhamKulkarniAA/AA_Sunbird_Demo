include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

inputs = {
  aws_access_key_id     = get_env("AWS_ACCESS_KEY_ID")
  aws_secret_access_key = get_env("AWS_SECRET_ACCESS_KEY")
  aws_region            = get_env("AWS_REGION")
}
