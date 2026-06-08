# Shared multi-tenant application layer (layer 1). Consumes the platform baseline.
terraform {
  source = "${get_repo_root()}/modules//artifact"
}

dependency "platform" {
  config_path = "${dirname(find_in_parent_folders("env.hcl"))}/platform"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "fmt", "show", "output"]
  mock_outputs = {
    id            = "mock-platform-id"
    token         = "mock-platform-token"
    tags          = {}
    artifact_path = "/tmp/mock-platform.json"
    summary = {
      id            = "mock-platform-id"
      token         = "mock-platform-token"
      artifact_path = "/tmp/mock-platform.json"
    }
  }
}

inputs = {
  component  = "app-layer"
  output_dir = "${get_repo_root()}/.artifacts"
  upstream = {
    platform = dependency.platform.outputs.summary
  }
}
