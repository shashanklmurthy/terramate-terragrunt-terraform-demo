include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/modules//artifact"
}

# DATA dependency on foundation. This is what Terramate parses to (a) order runs and
# (b) treat application as a dependent of foundation for --include-all-dependents.
dependency "foundation" {
   config_path = "../foundation"

  # Allow plan/validate to run before foundation has been applied (no real state yet).
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "fmt", "show", "output"]
  mock_outputs = {
    id            = "mock-foundation-id"
    token         = "mock-foundation-token"
    tags          = {}
    artifact_path = "/tmp/mock-foundation.json"
    summary = {
      id            = "mock-foundation-id"
      token         = "mock-foundation-token"
      artifact_path = "/tmp/mock-foundation.json"
    }
  }
}

inputs = {
  project     = "demo"
  environment = "dev"
  component   = "application"
  output_dir  = "${get_repo_root()}/.artifacts"
  extra_tags  = include.root.locals.default_tags

  # Consume foundation's outputs — this is the real data flow.
  upstream = {
    foundation = dependency.foundation.outputs.summary
  }
}
