output "api_urls" {
  value = { for environment, settings in local.profiles : environment => "http://127.0.0.1:${settings.proxy_port}" }
}

output "warning" {
  value = "LOCAL HTTP LAB ONLY. Both profiles share this Terraform state. Destroy removes BOTH deployments and their credentials."
}
