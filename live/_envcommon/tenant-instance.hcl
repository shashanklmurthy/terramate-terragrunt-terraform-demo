# Single-tenant dedicated instance. No dependency on the shared platform chain.
terraform {
  source = "${get_repo_root()}/modules//artifact"
}

inputs = {
  component  = "tenant-instance"
  output_dir = "${get_repo_root()}/.artifacts"
  upstream   = []
}
