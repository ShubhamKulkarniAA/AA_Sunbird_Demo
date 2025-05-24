include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

inputs = {
  bucket_name  = include.root.inputs.bucket_name
  schemas_path = "${get_terragrunt_dir()}/schemas"       # Relative path to your local schemas folder
}
