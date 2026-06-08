# Single-tenant dedicated account: acme (example tenant A).
locals {
  account_name  = "acme"
  customer_name = "acme"
  tenancy       = "single-tenant"
  project       = "demo"
}
