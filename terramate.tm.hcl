# Terramate project-wide configuration.
terramate {
  config {
    git {
      default_branch = "main"
    }

    # Terragrunt change detection is auto-enabled when a Terragrunt stack exists.
    # We set it to "force" so the demo behaves identically regardless of detection heuristics.
    change_detection {
      terragrunt {
        enabled = "force" # auto | force | off
      }
    }
  }
}
