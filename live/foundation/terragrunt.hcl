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
  component   = "foundation"
  output_dir  = "${get_repo_root()}/.artifacts"
  extra_tags  = include.root.locals.default_tags

  # foundation seeds the chain; no upstream.
  upstream = {}
}
