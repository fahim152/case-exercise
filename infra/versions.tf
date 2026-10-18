terraform {
  required_version = ">= 1.5.0, < 2.0.0"   # Avoid possible unverified breaking changes from a future Terraform major version.

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.6.0"
    }
  }
}

provider "docker" {}
