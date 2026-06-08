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

  # Re-roll the token whenever the identity changes, so dependents observe a new value.
  keepers = {
    id = module.labels.id
  }
}

resource "local_file" "artifact" {
  filename = "${var.output_dir}/${module.labels.id}.json"
  content = jsonencode({
    id       = module.labels.id
    tags     = module.labels.tags
    token    = random_string.token.result
    upstream = var.upstream
  })
}
