provider "tls" {}

provider "aws" {
  region = var.aws_region
}

locals {
  global_values_keys_file         = "${var.base_location}/../global-keys-values.yaml"
  jwt_script_location             = "${var.base_location}/../../../../scripts/jwt-keys.py"
  rsa_script_location             = "${var.base_location}/../../../../scripts/rsa-keys.py"
  global_values_jwt_file_location = "${var.base_location}/../../../../scripts/global-values-jwt-tokens.yaml"
  global_values_rsa_file_location = "${var.base_location}/../../../../scripts/global-values-rsa-keys.yaml"
  global_values_yaml              = "${var.base_location}/../global-values.yaml"
}

resource "random_password" "generated_string" {
  length  = 16
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "random_password" "encryption_string" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "null_resource" "generate_jwt_keys" {
  triggers = {
    jwt_key = random_password.generated_string.result
  }

  provisioner "local-exec" {
    command = <<EOT
      python3 ${local.jwt_script_location} ${random_password.generated_string.result} && \
      yq eval-all 'select(fileIndex == 0) *+ {"global": (select(fileIndex == 0).global * load("${local.global_values_jwt_file_location}"))}' -i ${local.global_values_yaml}
    EOT
  }
}

resource "null_resource" "generate_rsa_keys" {
  triggers = {
    rsa_count = var.rsa_keys_count
  }

  provisioner "local-exec" {
    command = <<EOT
      python3 ${local.rsa_script_location} ${var.rsa_keys_count} && \
      yq eval-all 'select(fileIndex == 0) *+ {"global": (select(fileIndex == 0).global * load("${local.global_values_rsa_file_location}"))}' -i ${local.global_values_yaml}
    EOT
  }
}

resource "aws_s3_object" "upload_global_jwt_values_yaml" {
  bucket = var.bucket_name
  key    = "${var.environment}-global-values-jwt-tokens.yaml"
  source = local.global_values_jwt_file_location
  etag   = filesha256(local.global_values_jwt_file_location)

  depends_on = [null_resource.generate_jwt_keys]
}

resource "aws_s3_object" "upload_global_rsa_values_yaml" {
  bucket = var.bucket_name
  key    = "${var.environment}-global-values-rsa-keys.yaml"
  source = local.global_values_rsa_file_location
  etag   = filesha256(local.global_values_rsa_file_location)

  depends_on = [null_resource.generate_rsa_keys]
}

resource "null_resource" "terrahelp_encryption" {
  count = var.enable_terrahelp ? 1 : 0

  triggers = {
    encryption_key = random_password.generated_string.result
  }

  provisioner "local-exec" {
    command = "terrahelp encrypt -simple-key=${random_password.generated_string.result} -file=${local.global_values_keys_file}"
  }
}
