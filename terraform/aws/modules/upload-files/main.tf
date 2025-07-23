
# Local to hold the base URL for your S3 bucket where schemas will be uploaded
locals {
  cloud_storage_schema_url = "https://${var.bucket_name}.s3.amazonaws.com"

  # List all JSON template files (ending with .json.tpl) inside the schemas directory
  schema_templates = fileset(var.schemas_path, "*.json.tpl")

  # Render each JSON template with the cloud_storage_schema_url variable
  rendered_schemas = {
    for tpl in local.schema_templates :
    tpl => templatefile("${var.schemas_path}/${tpl}", {
      cloud_storage_schema_url = local.cloud_storage_schema_url
    })
  }
}

# Upload each rendered schema JSON file to S3 (removing the .tpl extension)
resource "aws_s3_bucket_object" "schemas" {
  for_each = local.rendered_schemas

  bucket       = var.bucket_name
  key          = replace(each.key, ".tpl", "") # upload as .json file
  content      = each.value
  content_type = "application/json"
}
