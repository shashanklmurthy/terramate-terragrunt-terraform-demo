stack {
  name        = "analytics dev"
  description = "Shared multi-tenant analytics layer"
  after       = ["/live/shared/us-east-1/dev/app-layer"]
  id          = "3186953e-1ef2-44f0-981d-2c73c62daad6"
  tags        = ["tenancy-multi-tenant", "component-analytics"]
}
