# Layered module: composes the leaf `labels` module, then creates local resources.
# NOTE on the source path "../labels":
#   This resolves because the live units source the WHOLE modules/ directory via the Terragrunt
#   "//" subdir mechanism (source = ".../modules//artifact"), so modules/labels is copied alongside
#   modules/artifact into the Terragrunt cache. See the operator manual for details.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  component   = var.component
  tenant_id   = var.tenant_id
  extra_tags  = var.extra_tags
}

resource "random_string" "token" {
  length  = 12
  special = false
  upper   = false

  # Re-roll when identity or propagated contract_version changes so dependency drift
  # surfaces in the main plan section (not only output diffs).
  keepers = {
    id               = module.labels.id
    contract_version = local.contract_version != null ? local.contract_version : ""
  }
}
