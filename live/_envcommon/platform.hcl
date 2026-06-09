# Shared multi-tenant platform baseline (layer 0). No upstream dependencies.
terraform {
  source = "${get_repo_root()}/modules//artifact"
}

inputs = {
  component  = "platform"
  output_dir = "${get_repo_root()}/.artifacts"
  upstream   = []
}
