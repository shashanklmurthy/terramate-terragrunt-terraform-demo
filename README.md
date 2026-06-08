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

live/standalone  (layer 0, no dependency on the chain above)
```

`live/standalone` has no `dependency` blocks — it is independent of the chain above.

Each chained unit produces a JSON artifact in `.artifacts/` and exposes a `summary` output. The next
layer consumes that summary through a Terragrunt `dependency` block.

## What each requirement maps to

| Requirement | Where |
|---|---|
| Modules vs. live | `modules/` (Terraform) vs `live/` (Terragrunt) |
| Layered modules | `modules/artifact` composes `modules/labels` |
| Transitive auto-run | Change `foundation` → `application` + `reporting` re-run |
| `generate` + `path_relative_to_include()` | `root.hcl` — state key and generated `stack_meta.tf` |

## Prerequisites

Versions are pinned in [`.tool-versions`](.tool-versions) (single source of truth).

| Tool | Local install | Version file |
|---|---|---|
| Terraform | [tfenv](https://github.com/tfutils/tfenv) | `.terraform-version` |
| Terragrunt | [tgenv](https://github.com/cunymatthieu/tgenv) | `.terragrunt-version` |
| Terramate | e.g. `brew install terramate` | `.tool-versions` only |

Sync version files from `.tool-versions`, then install:

```bash
# write .terraform-version and .terragrunt-version (keep in sync with .tool-versions)
awk '/^terraform /  {print $2}' .tool-versions > .terraform-version
awk '/^terragrunt / {print $2}' .tool-versions > .terragrunt-version

tfenv install && tfenv use
tgenv install && tgenv use

terraform version
terragrunt --version
terramate version    # needs ≥ ~0.11 for --include-all-dependents
```

CI installs all three from `.tool-versions` via [`.github/actions/setup-asdf`](.github/actions/setup-asdf).

## First-time bootstrap

Run once after cloning. Terramate requires a clean git working tree (commit or stash changes first).

```bash
# 1. Import live/ units as Terramate stacks (writes live/*/stack.tm.hcl)
terramate create --all-terragrunt

# 2. Init and apply everything, in dependency order
terramate run -- terragrunt init -input=false
terramate run -- terragrunt apply -auto-approve -input=false
```

Verify:

```bash
terramate list --run-order
# live/foundation
# live/standalone
# live/application
# live/reporting

ls .artifacts/    # four JSON files after full apply
```

## Common commands

### List and inspect stacks

```bash
terramate list                                    # all stacks
terramate list --run-order                        # dependency order
terramate list --tags reconcile                   # foundation + application only
terramate experimental run-graph -o /tmp/stacks.dot
```

### Run all stacks (sequential, in order)

```bash
terramate run -- terragrunt init -input=false
terramate run -- terragrunt plan -input=false
terramate run -- terragrunt apply -auto-approve -input=false
```

### Change-driven runs (the headline feature)

After editing and **committing** a `live/` change:

```bash
# what changed vs main (no dependents)
terramate list --changed --git-change-base main

# changed + transitive dependents, in run order
terramate list --changed --include-all-dependents --git-change-base main --run-order

# apply only what changed (+ dependents), in order
terramate run --changed --include-all-dependents --git-change-base main -- \
  terragrunt apply -auto-approve -input=false
```

In CI the git base differs: PRs use `origin/<base_ref>`, merge deploy uses `HEAD^`.

### Format checks

```bash
terraform fmt -check -recursive modules/
terragrunt hcl fmt --check
```

### Drift and reconcile (local)

```bash
# per-stack plan; exit 2 = drift (meaningful only with persistent state between runs)
for stack in $(terramate list); do
  ( cd "$stack" && terragrunt plan -detailed-exitcode -lock=false -input=false ) || \
    echo "drift or error in $stack (exit $?)"
done

# re-apply reconcile-tagged stacks only (foundation + application; reporting excluded)
terramate run --tags reconcile -- terragrunt apply -auto-approve -lock=false -input=false
```

## Verify transitive change detection

This is the proof the repo exists for. Ensure `git status` is clean before starting.

### Case 1 — change only `foundation`

```bash
git switch -c demo/change-foundation

# edit live/foundation/terragrunt.hcl, then:
git add live/foundation/terragrunt.hcl
git commit -m "change: tweak foundation input"

terramate list --changed --include-all-dependents --git-change-base main --run-order
# expected: live/foundation, live/application, live/reporting
# (standalone is NOT included — it doesn't depend on foundation)
```

### Case 2 — change only `application`

```bash
git switch main
git switch -c demo/change-application

# edit live/application/terragrunt.hcl only, then commit

terramate list --changed --include-all-dependents --git-change-base main --run-order
# expected: live/application, live/reporting  (NOT foundation)
```

Always pass `--git-change-base` explicitly when testing on a branch — without it, Terramate may
compare against the wrong ref or include extra stacks from uncommitted files.

## CI workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-preview` | PR → `main` | fmt + hclfmt + checkov; one `terramate run` plan; **one sticky PR comment per stack** |
| `deploy` | push → `main` | single ordered `terramate run` apply (changed + dependents) |
| `drift` | daily cron | `terramate run` + `plan -detailed-exitcode` on every stack; fails on drift |
| `reconcile` | daily cron | ordered apply of `--tags reconcile` stacks |

**PR comments:** One summary comment plus one sticky comment per changed stack (ASCII plan).
Comments for stacks that drop out of the change set are removed on the next run. Rendered plan
UI requires [Terramate Cloud](https://terramate.io/docs/cloud/integrations/github) + `--sync-preview`.

Drift detection in CI demonstrates the correct workflow shape but won't catch real drift until
`root.hcl` uses a persistent remote backend (state survives between runs).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Error: repository has untracked files` | Commit or stash; Terramate refuses to run with dirty git |
| Cycle / wrong `after` in stacks | Keep `live/*` flat (siblings, never nested); re-run `terramate create --all-terragrunt` |
| `dependency ... has no outputs` | Run full apply once, or rely on `mock_outputs` for plan |
| Every stack always "changed" | Something writes into a tracked dir — check `.gitignore` |
| `--include-all-dependents` not recognized | Upgrade Terramate (needs 2024+ build) |
| Module-only edits don't trigger stacks | Function-based `source` paths can hide module changes; demo triggers on *live-unit* edits |

## Further reading

See [`OPERATOR_MANUAL.md`](OPERATOR_MANUAL.md) for the mental model, `generate` blocks, the `//`
source gotcha, and CI integration details.
