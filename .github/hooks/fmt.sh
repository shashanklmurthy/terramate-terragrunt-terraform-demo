#!/usr/bin/env bash
set -euo pipefail

# Terraform modules (not Terramate stacks).
terraform fmt -recursive modules/

# Root Terragrunt/Terramate HCL (root.hcl, terramate.tm.hcl) — not Terramate stacks.
terragrunt hcl fmt

# All live stacks via Terramate (matches CI).
terramate run \
  --disable-safeguards=git-untracked,git-uncommitted \
  -- \
  terragrunt hcl fmt
