include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/modules//artifact"
}

dependency "application" {
  config_path = "../application"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "fmt", "show", "output"]
  mock_outputs = {
    id            = "mock-application-id"
    token         = "mock-application-token"
    tags          = {}
    artifact_path = "/tmp/mock-application.json"
    summary = {
      id            = "mock-application-id"
      token         = "mock-application-token"
      artifact_path = "/tmp/mock-application.json"
    }
  }
}

inputs = {
  project     = "demo"
  environment = "dev"
  component   = "reporting"
  output_dir  = "${get_repo_root()}/.artifacts"
  extra_tags  = include.root.locals.default_tags

  # reporting depends on application -> transitively on foundation.
  upstream = {
    application = dependency.application.outputs.summary
  }
}
