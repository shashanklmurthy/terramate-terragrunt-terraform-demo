# Leaf module: produces a standardized id and a merged tag map. No resources — pure convention.
locals {
  id = lower(replace("${var.project}-${var.environment}-${var.component}", " ", "-"))

  convention_tags = {
    "project"     = var.project
    "environment" = var.environment
    "component"   = var.component
    "managed_by"  = "terragrunt+terramate"
  }

  tags = merge(local.convention_tags, var.extra_tags)
}
