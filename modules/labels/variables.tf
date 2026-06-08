variable "project" {
  description = "Project / repo identifier."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, prod)."
  type        = string
}

variable "component" {
  description = "Logical component name for this stack."
  type        = string
}

variable "tenant_id" {
  description = "Optional customer/tenant identifier for single-tenant instances."
  type        = string
  default     = null
}

variable "extra_tags" {
  description = "Additional tags merged on top of the convention tags."
  type        = map(string)
  default     = {}
}
