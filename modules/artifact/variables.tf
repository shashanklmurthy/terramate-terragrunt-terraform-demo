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

variable "upstream" {
  description = "Arbitrary data from upstream stacks, embedded into this artifact to prove the data flow."
  type        = any
  default     = {}
}
