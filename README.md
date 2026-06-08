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

## Mental model

| Tool | Owns | Unit of work |
|------|------|--------------|
| Terraform | resource definitions | a *module* (`modules/*`) |
| Terragrunt | per-environment wiring, DRY config, dependencies | a *unit* (`live/*/terragrunt.hcl`) |
| Terramate | change detection + orchestration across units | a *stack* (`live/*/stack.tm.hcl`) |

A Terragrunt **unit** and a Terramate **stack** are the same directory: `terragrunt.hcl` makes it
deployable, `stack.tm.hcl` makes it orchestratable.

### Data flow

1. `live/foundation` runs `modules/artifact` (component = foundation). It outputs `summary`.
2. `live/application` declares `dependency "foundation"` and feeds `dependency.foundation.outputs.summary`
   into its own `upstream` input.
3. `live/reporting` declares `dependency "application"` and feeds its summary in turn.
4. `live/standalone` has **no** `dependency` blocks — independent of the chain above.

`dependency` blocks do two things at once:
- **Runtime:** Terragrunt fetches upstream outputs (`mock_outputs` cover plan-before-apply).
- **Orchestration:** Terramate parses them to set `after` ordering and compute dependents.

## What each requirement maps to

| Requirement | Where |
|---|---|
| Modules vs. live | `modules/` (Terraform) vs `live/` (Terragrunt) |
| Layered modules | `modules/artifact` composes `modules/labels` |
| Transitive auto-run | Change `foundation` → `application` + `reporting` re-run |
| `generate` + `path_relative_to_include()` | `root.hcl` — state key and generated `stack_meta.tf` |

## Prerequisites

All versions are pinned in [`.tool-versions`](.tool-versions) — the single source of truth for local
and CI.

| Tool | Local install |
|---|---|
| Terraform | [tfenv](https://github.com/tfutils/tfenv) |
| Terragrunt | [tgenv](https://github.com/cunymatthieu/tgenv) |
| Terramate | e.g. `brew install terramate` (no tfenv/tgenv plugin) |

```bash
TF_VER=$(awk '/^terraform / {print $2}' .tool-versions)
TG_VER=$(awk '/^terragrunt / {print $2}' .tool-versions)

tfenv install "$TF_VER" && tfenv use "$TF_VER"
tgenv install "$TG_VER" && tgenv use "$TG_VER"

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

## Change detection and ordering

- `terramate list` / `run` with `--changed` selects stacks whose tracked files changed in git.
- **By default, dependents are NOT pulled in.** Opt in with:
  - `--include-all-dependents` — direct and transitive dependents
  - `--include-direct-dependents` — immediate dependents only
  - `--only-all-dependents` — dependents only (replaces the changed set)
- Filters follow **data** dependencies (Terragrunt `dependency` blocks), not ordering-only hints
  (`stack.before/after`). That's why units use real `dependency` blocks.
- Execution order honors `after`. `standalone` has no `after` and nothing depends on it.

Canonical change-driven command:

```bash
terramate run --changed --include-all-dependents -- terragrunt apply -auto-approve
```

In CI, add `--git-change-base origin/main` (PRs) or `HEAD^` (push to main).

If your Terramate build is too old for `--include-all-dependents`, upgrade — or force stacks changed
with `terramate trigger live/application` before `terramate run --changed`.

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

## Generated files (`root.hcl`)

Because each unit sets `terraform.source`, generated files land in the **Terragrunt cache** working
directory (not the unit dir):

- `versions.tf` — required Terraform version + `random`/`local` providers
- `provider.tf` — empty provider blocks
- `backend.tf` — local backend; state path = `<repo>/.local-state/<path_relative_to_include()>/terraform.tfstate`
- `stack_meta.tf` — generated `stack_path` output using `path_relative_to_include()`

Inspect without applying:

```bash
cd live/application
terragrunt init
find .terragrunt-cache -name '*.tf' | xargs -I{} sh -c 'echo "== {} =="; cat {}'
```

## The `//` in `terraform.source`

`source = "${get_repo_root()}/modules//artifact"`

The `//` is the go-getter "subdir" separator. Terragrunt copies everything **before** `//`
(`modules/`) into its cache, then uses the subdir **after** `//` (`artifact`) as the Terraform root.
Without this, `modules/artifact`'s `module "labels" { source = "../labels" }` would escape the
copied tree and fail.

## Why `.artifacts/` and `.local-state/` are gitignored

Since Terramate v0.11, **untracked and uncommitted files count as changes**. If `local_file` wrote
artifacts into a tracked `live/*` directory, every stack would always look "changed" and the
change-detection demo would be meaningless.

## CI workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-preview` | PR → `main` | fmt + hclfmt + checkov; one `terramate run` plan; **one PR comment per changed stack** ([GetTerminus/terraform-pr-commenter](https://github.com/GetTerminus/terraform-pr-commenter)) |
| `deploy` | push → `main` | single ordered `terramate run` apply (changed + dependents) |
| `drift` | daily cron | `terramate run` + `plan -detailed-exitcode` on every stack; fails on drift |
| `reconcile` | daily cron | ordered apply of `--tags reconcile` stacks |

**PR comments:** During plan, stdout for each changed stack is captured under
`.github/plan-artifacts/` (e.g. `live-foundation.txt` + `live-foundation.exitcode`). A matrix job
posts one comment per stack in Terramate run order via
[GetTerminus/terraform-pr-commenter](https://github.com/GetTerminus/terraform-pr-commenter) (a
maintained fork of robburger/terraform-pr-commenter), passing each capture as `commenter_plan_path`
and setting `TF_WORKSPACE` to the stack path (e.g. `live/foundation`).

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
| Module-only edits don't trigger stacks | Function-based `source` paths can hide module changes; demo triggers on *live-unit* edits. Plain relative `source` fixes detection but loses the `//` copy trick |
