locals {
  global_values_cloud_file = "${var.base_location}/../global-cloud-values.yaml"
}

resource "local_sensitive_file" "global_cloud_values_yaml" {
  content = templatefile("${path.module}/global-cloud-values.yaml.tfpl", {
    env                       = var.env,
    environment               = var.environment,
    building_block            = var.building_block,
    aws_s3_bucket_name        = var.bucket_name,
    aws_s3_private_path       = var.s3_private_path,
    aws_s3_public_path        = var.s3_public_path,
    aws_s3_dial_state_path    = var.s3_dial_state_path,
    private_ingressgateway_ip = var.private_ingressgateway_ip,
    encryption_string         = var.encryption_string,
    random_string             = var.random_string
    aws_access_key_id         = var.aws_access_key_id
    aws_secret_access_key     = var.aws_secret_access_key
    aws_region                = var.aws_region
    aws_s3_public_bucket_name = var.aws_s3_public_bucket_name
  })
  filename = local.global_values_cloud_file
}

resource "null_resource" "upload_global_cloud_values_yaml" {
  triggers = {
    command = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "aws s3 cp ${local.global_values_cloud_file} s3://${var.bucket_name}/${var.environment}-global-cloud-values.yaml --region ${var.aws_region}"
  }
  depends_on = [local_sensitive_file.global_cloud_values_yaml]
}
