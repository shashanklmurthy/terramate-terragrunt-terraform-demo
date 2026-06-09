include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "envcommon" {
  path   = "${dirname(find_in_parent_folders("root.hcl"))}/live/_envcommon/platform.hcl"
  expose = true
}

inputs = {
  contract_version = "2025-01"
}
