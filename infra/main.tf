locals {
  # Read both profiles explicitly; one apply creates both local environments.
  profiles = {
    test       = jsondecode(file("${path.module}/environments/test.json"))
    production = jsondecode(file("${path.module}/environments/production.json"))
  }

  mock_context = abspath("${path.module}/../MockBackend")
  source_files = sort([for file in fileset(local.mock_context, "**") : file
    if !can(regex("(^|/)(node_modules|bin|obj|wwwroot|data)(/|$)|(^|/)\\.env|\\.db|\\.DS_Store$", file))
  ])
  source_hash     = sha256(join("", [for file in local.source_files : "${file}:${filesha256("${local.mock_context}/${file}")}"]))
  gateway_context = abspath("${path.module}/../gateway")
  gateway_hash    = sha256(join("", [for file in ["Dockerfile", ".dockerignore", "bootstrap.sh", "entrypoint.sh"] : filesha256("${local.gateway_context}/${file}")]))
}

# The backend has no host port and no external network attachment.
resource "docker_network" "backend" {
  for_each = local.profiles
  name     = "product-order-${each.key}-backend"
  internal = true

  lifecycle {
    precondition {
      condition     = terraform.workspace == "default"
      error_message = "Use the default workspace for the combined lab. Reconcile any old production workspace before applying."
    }
    precondition {
      condition = try(
        each.value.proxy_port >= 1024 && each.value.proxy_port <= 65535 && floor(each.value.proxy_port) == each.value.proxy_port
        && length(distinct([for profile in values(local.profiles) : tonumber(profile.proxy_port)])) == length(local.profiles),
        false
      )
      error_message = "Environment files must specify different integer proxy_port values from 1024 to 65535."
    }
    precondition {
      condition = try(
        each.value.upstream_timeout_ms >= 100 && each.value.upstream_timeout_ms <= 10000 && floor(each.value.upstream_timeout_ms) == each.value.upstream_timeout_ms
        && each.value.cache_ttl_seconds >= 1 && each.value.cache_ttl_seconds <= 300 && floor(each.value.cache_ttl_seconds) == each.value.cache_ttl_seconds,
        false
      )
      error_message = "Use integer timeouts from 100 to 10000 ms and cache TTLs from 1 to 300 seconds."
    }
    precondition {
      condition = try(
        each.value.requests_per_second >= 1 && each.value.requests_per_second <= 100 && floor(each.value.requests_per_second) == each.value.requests_per_second
        && each.value.requests_per_minute >= 20 && each.value.requests_per_minute <= 6000 && floor(each.value.requests_per_minute) == each.value.requests_per_minute
        && each.value.requests_per_minute >= each.value.requests_per_second,
        false
      )
      error_message = "Use integer quotas: 1-100 per second, 20-6000 per minute, with the minute quota at least the second quota."
    }
  }
}

resource "docker_network" "edge" {
  for_each = local.profiles
  name     = "product-order-${each.key}-edge"
}

resource "docker_volume" "secrets" {
  for_each = local.profiles
  name     = "product-order-${each.key}-credentials"
}

resource "docker_image" "backend" {
  for_each = local.profiles
  name     = "product-order-${each.key}-mock:${substr(local.source_hash, 0, 12)}"
  build {
    context = local.mock_context
  }
  triggers = {
    source = local.source_hash
  }
}

resource "docker_container" "backend" {
  for_each     = local.profiles
  name         = "product-order-${each.key}-mock"
  image        = docker_image.backend[each.key].image_id
  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 120
  log_driver   = "json-file"
  log_opts     = { "max-size" = "10m", "max-file" = "2" }
  env = [
    "Logging__LogLevel__Microsoft.AspNetCore=Warning",
  ]

  networks_advanced {
    name    = docker_network.backend[each.key].name
    aliases = ["mock-backend"]
  }
}

resource "docker_image" "kong" {
  for_each = local.profiles
  name     = "product-order-${each.key}-gateway:${substr(local.gateway_hash, 0, 12)}"
  build {
    context = local.gateway_context
  }
  triggers = { source = local.gateway_hash }
}

resource "docker_container" "gateway" {
  for_each     = local.profiles
  name         = "product-order-${each.key}-gateway"
  image        = docker_image.kong[each.key].image_id
  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 120
  depends_on   = [docker_container.backend]
  log_driver   = "json-file"
  log_opts     = { "max-size" = "10m", "max-file" = "2" }

  env = [
    "KONG_DATABASE=off",
    "KONG_DECLARATIVE_CONFIG=/tmp/kong.yml",
    "KONG_ADMIN_LISTEN=off",
    "KONG_ADMIN_GUI_LISTEN=off",
    "KONG_PROXY_LISTEN=0.0.0.0:8000",
    "KONG_ROUTER_FLAVOR=traditional_compatible",
    "KONG_NGINX_WORKER_PROCESSES=1",
    "KONG_PROXY_ACCESS_LOG=/dev/stdout lab",
    # Raw Nginx errors can include query strings; sanitized status/timing logs remain.
    "KONG_PROXY_ERROR_LOG=/dev/null",
    "KONG_NGINX_HTTP_LOG_FORMAT=lab '$request_method $uri $status $request_time'",
    "KONG_NGINX_HTTP_CLIENT_MAX_BODY_SIZE=16k",
  ]

  # Non-secret routing only. Uploaded content is stored in Terraform state.
  upload {
    file = "/tmp/routes.yml"
    content = templatefile("${path.module}/../gateway/kong.yml", {
      upstream_timeout_ms = each.value.upstream_timeout_ms
      requests_per_second = each.value.requests_per_second
      requests_per_minute = each.value.requests_per_minute
      cache_ttl_seconds   = each.value.cache_ttl_seconds
    })
    permissions = "0644"
  }

  volumes {
    volume_name    = docker_volume.secrets[each.key].name
    container_path = "/var/lib/lab-secrets"
  }

  networks_advanced {
    name = docker_network.backend[each.key].name
  }
  networks_advanced {
    name = docker_network.edge[each.key].name
  }
  ports {
    internal = 8000
    external = each.value.proxy_port
    ip       = "127.0.0.1"
  }
  healthcheck {
    test         = ["CMD", "kong", "health"]
    interval     = "5s"
    timeout      = "3s"
    start_period = "20s"
    retries      = 12
  }
}
