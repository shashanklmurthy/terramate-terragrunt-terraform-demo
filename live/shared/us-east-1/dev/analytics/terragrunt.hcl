include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/live/_envcommon/analytics.hcl"
  expose = true
}

inputs = {
  extra_tags = include.root.locals.default_tags
}
