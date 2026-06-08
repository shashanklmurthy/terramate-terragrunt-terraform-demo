# terramate-terragrunt-terraform-demo

A minimal, **fully local** (no cloud) reference showing **Terraform + Terragrunt + Terramate**
working together:

- **Terraform** defines reusable modules in `modules/`.
- **Terragrunt** defines the deployable "live" units in `live/`, wires them together with
  `dependency` blocks, and generates provider/backend/version files.
- **Terramate** orchestrates: it detects which units changed and runs them — plus everything that
  transitively depends on them — in the correct order.

Providers used: `hashicorp/random` and `hashicorp/local`. No credentials, no remote state.

## Architecture

```
modules/labels    (leaf: naming + tags, no resources)
        ▲
        │ used by
        │
modules/artifact  (layered: labels + random_string + local_file)
        ▲
        │ sourced by every live unit
        │
live/foundation ──▶ live/application ──▶ live/reporting
   (layer 0)           (layer 1)            (layer 2)
```

Each live unit produces a JSON artifact in `.artifacts/` and exposes a `summary` output. The next
layer consumes that summary through a Terragrunt `dependency` block.

## What each requirement maps to

- **Modules vs. live** — `modules/` (Terraform) vs `live/` (Terragrunt).
- **Layered modules** — `modules/artifact` composes `modules/labels`.
- **Transitive auto-run** — change `foundation`, and `application` + `reporting` re-run after it.
- **`generate` + `path_relative_to_include()`** — see `root.hcl`; the state key and a generated
  `stack_meta.tf` both derive from `path_relative_to_include()`.

## Quick start

```bash
# one-time
terramate create --all-terragrunt        # import live units as stacks
terramate run -- terragrunt init
terramate run -- terragrunt apply -auto-approve

# see run order
terramate list --run-order

# change-driven, dependency-aware run (the headline feature)
terramate run --changed --include-all-dependents -- terragrunt apply -auto-approve
```

See `OPERATOR_MANUAL.md` for how it all fits together and how to extend it.
