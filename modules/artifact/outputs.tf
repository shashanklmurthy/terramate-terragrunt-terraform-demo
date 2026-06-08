output "id" {
  value = module.labels.id
}

output "token" {
  value = random_string.token.result
}

output "tags" {
  value = module.labels.tags
}

locals {
  # Repo-relative path — portable across laptops and CI runners.
  artifact_rel_path = ".artifacts/${module.labels.id}.json"
  platform_tier     = try(var.upstream.platform.tags["platform-tier"], try(var.upstream.app_layer.platform_tier, ""))
}

output "artifact_path" {
  value = local.artifact_rel_path
}

output "summary" {
  description = "Compact object consumed by downstream stacks via Terragrunt dependency blocks."
  value = {
    id            = module.labels.id
    token         = random_string.token.result
    artifact_path = local.artifact_rel_path
    tags          = module.labels.tags
    platform_tier = local.platform_tier != "" ? local.platform_tier : null
  }
}

output "upstream_chain" {
  description = "Upstream summaries passed through this stack for transitive propagation demos."
  value       = var.upstream
}
