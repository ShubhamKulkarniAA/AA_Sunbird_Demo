output "encryption_string" {
  value     = random_password.encryption_string.result
  sensitive = true
}

output "random_string" {
  value     = random_password.generated_string.result
  sensitive = true
}

output "base_location" {
  value = var.base_location
}

output "jwt_script_location" {
  value = local.jwt_script_location
}
