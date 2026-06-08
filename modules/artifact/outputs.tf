output "id" {
  value = module.labels.id
}

output "token" {
  value = random_string.token.result
}

output "tags" {
  value = module.labels.tags
}

output "artifact_path" {
  value = local_file.artifact.filename
}

output "summary" {
  description = "Compact object consumed by downstream stacks via Terragrunt dependency blocks."
  value = {
    id            = module.labels.id
    token         = random_string.token.result
    artifact_path = local_file.artifact.filename
  }
}
