include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/live/_envcommon/tenant-instance.hcl"
  expose = true
}

inputs = {
  extra_tags = merge(include.root.locals.default_tags, {
    "cost-center" = "acme-ops-123"
  })
  tenant_id = include.root.locals.customer_name
}
