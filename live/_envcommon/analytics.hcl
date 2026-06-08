# Shared multi-tenant analytics layer (layer 2). Consumes the app layer.
terraform {
  source = "${get_repo_root()}/modules//artifact"
}

dependency "app_layer" {
  config_path = "${dirname(find_in_parent_folders("env.hcl"))}/app-layer"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "fmt", "show", "output"]
  mock_outputs = {
    id            = "mock-app-layer-id"
    token         = "mock-app-layer-token"
    tags          = {}
    artifact_path = ".artifacts/mock-app-layer.json"
    summary = {
      id            = "mock-app-layer-id"
      token         = "mock-app-layer-token"
      artifact_path = ".artifacts/mock-app-layer.json"
    }
  }
}

inputs = {
  component  = "analytics"
  output_dir = "${get_repo_root()}/.artifacts"
  upstream = {
    app_layer = dependency.app_layer.outputs.summary
  }
}
