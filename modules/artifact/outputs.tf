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
  # Upstream chain wins when present (last entry = root platform). Local is the fallback (platform root).
  # Nullable: dedicated tenant stacks have neither upstream nor a local contract.
  last_upstream_contract_version = length(var.upstream) > 0 ? try(
    var.upstream[length(var.upstream) - 1].contract_version,
    null,
  ) : null
  contract_version = local.last_upstream_contract_version != null ? local.last_upstream_contract_version : var.contract_version
}

output "artifact_path" {
  value = local.artifact_rel_path
}

output "summary" {
  description = "Compact object consumed by downstream stacks via Terragrunt dependency blocks."
  value = {
    id               = module.labels.id
    token            = random_string.token.result
    artifact_path    = local.artifact_rel_path
    tags             = module.labels.tags
    contract_version = local.contract_version
  }
}

output "upstream_chain" {
  description = "Upstream summaries nearest-first, passed through for transitive propagation demos."
  value       = var.upstream
}
