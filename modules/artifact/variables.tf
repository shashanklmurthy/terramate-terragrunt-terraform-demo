variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "component" {
  type = string
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
