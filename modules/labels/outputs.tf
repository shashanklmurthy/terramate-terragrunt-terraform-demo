output "id" {
  description = "Standardized identifier: <project>-<environment>-<component>."
  value       = local.id
}

output "tags" {
  description = "Merged convention + extra tags."
  value       = local.tags
}
