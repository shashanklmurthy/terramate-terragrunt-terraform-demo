# Leaf module: produces a standardized id and a merged tag map. No resources — pure convention.
locals {
  id_prefix = var.tenant_id != null ? "${var.project}-${var.tenant_id}-${var.environment}" : "${var.project}-${var.environment}"
  id        = lower(replace("${local.id_prefix}-${var.component}", " ", "-"))

  convention_tags = merge(
    {
      "project"     = var.project
      "environment" = var.environment
      "component"   = var.component
      "managed_by"  = "terragrunt+terramate"
    },
    var.tenant_id != null ? { "tenant_id" = var.tenant_id } : {},
  )

  tags = merge(local.convention_tags, var.extra_tags)
}
