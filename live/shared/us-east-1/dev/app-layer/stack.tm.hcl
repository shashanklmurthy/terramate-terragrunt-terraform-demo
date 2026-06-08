stack {
  name        = "app-layer dev"
  description = "Shared multi-tenant application layer"
  after       = ["/live/shared/us-east-1/dev/platform"]
  id          = "c2a1ffe9-6bb8-4f6a-964d-25988ecf3088"
  tags        = ["reconcile", "tenancy-multi-tenant", "component-app-layer"]
}
