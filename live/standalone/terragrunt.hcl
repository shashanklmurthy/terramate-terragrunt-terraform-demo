include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/modules//artifact"
}

inputs = {
  project     = "demo"
  environment = "dev"
  component   = "standalone"
  output_dir  = "${get_repo_root()}/.artifacts"
  extra_tags  = include.root.locals.default_tags

  # No dependency blocks — this unit is independent of foundation → application → reporting.
  upstream = {}
}
