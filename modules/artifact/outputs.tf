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
  }
}
