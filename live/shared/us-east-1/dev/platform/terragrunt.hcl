include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/live/_envcommon/platform.hcl"
  expose = true
}

inputs = {
  extra_tags = merge(include.root.locals.default_tags, {
    "platform-tier" = "premium"
  })
}
