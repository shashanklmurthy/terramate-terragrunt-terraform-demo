variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "component" {
  type = string
}

variable "tenant_id" {
  description = "Optional customer/tenant identifier for single-tenant instances."
  type        = string
  default     = null
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

variable "output_dir" {
  description = "Directory where the artifact JSON file is written."
  type        = string
}

variable "contract_version" {
  description = "Local contract version fallback; used only when upstream is empty (platform root). Downstream stacks inherit from the upstream chain instead."
  type        = string
  default     = null
}

variable "upstream" {
  description = "Upstream stack summaries, nearest dependency first. Each layer prepends its dependency to the front of the chain passed downstream."
  type        = list(any)
  default     = []
}
