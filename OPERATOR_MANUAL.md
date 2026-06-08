# Operator manual

## Tool versions

All CLI versions are pinned in [`.tool-versions`](.tool-versions) — the single source of truth.

**Local:** terraform and terragrunt via tfenv/tgenv (see [README.md](README.md#prerequisites) for
setup). Install terramate separately (no tfenv/tgenv plugin), e.g. `brew install terramate`.

**CI:** `.github/actions/setup-asdf` reads `.tool-versions` via asdf.

## Mental model

Three tools, three jobs:

| Tool | Owns | Unit of work |
|------|------|--------------|
| Terraform | resource definitions | a *module* (`modules/*`) |
| Terragrunt | per-environment wiring, DRY config, dependencies | a *unit* (`live/*/terragrunt.hcl`) |
| Terramate | change detection + orchestration across units | a *stack* (`live/*/stack.tm.hcl`) |

A Terragrunt **unit** and a Terramate **stack** are the same directory: the `terragrunt.hcl` makes it
deployable, the `stack.tm.hcl` makes it orchestratable.

## How the layers connect (data flow)

1. `live/foundation` runs `modules/artifact` (component = foundation). It outputs `summary`.
2. `live/application` declares `dependency "foundation"` and feeds `dependency.foundation.outputs.summary`
   into its own `upstream` input.
3. `live/reporting` declares `dependency "application"` and feeds its summary in turn.
4. `live/standalone` has **no** `dependency` blocks — it is independent of the chain above.

The `dependency` blocks do two things at once:
- **Runtime:** Terragrunt fetches the upstream unit's outputs (with `mock_outputs` covering plan-before-apply).
- **Orchestration:** Terramate parses them to set `after` ordering and to compute dependents.

## How change detection + ordering actually behave

- `terramate list` / `run` with `--changed` selects only stacks whose tracked files changed in git.
- **By default, dependents are NOT pulled in.** You opt in:
  - `--include-all-dependents` — add stacks that depend on the changed ones (direct **and** transitive).
  - `--include-direct-dependents` — only the immediate dependents.
  - `--only-all-dependents` — replace the selection with just the dependents.
- Dependency filters only follow **data** dependencies (Terragrunt `dependency` blocks / Terramate
  output sharing). They ignore ordering-only relationships (`stack.before/after`, `dependencies.paths`).
  That's why our units use real `dependency` blocks, not just ordering hints.
- Execution order always honors `after`. `standalone` has no `after` and nothing depends on it, so
  it runs independently of the foundation → application → reporting chain.

Canonical change-driven command:

```bash
terramate run --changed --include-all-dependents -- terragrunt apply -auto-approve
```

In CI, add `--git-change-base origin/main` (PRs) or `HEAD^` (push to main).

### Fallback if your Terramate is too old for the flags

Upgrade is preferred. If you can't, force a stack to be considered changed with a trigger:

```bash
terramate trigger live/application
terramate trigger live/reporting
terramate run --changed -- terragrunt apply -auto-approve
```

## The `generate` blocks (in `root.hcl`)

Because each unit sets `terraform.source`, generated files land in the **Terragrunt cache** working
directory (not the unit dir):
- `versions.tf` — required Terraform version + `random`/`local` providers.
- `provider.tf` — empty provider blocks.
- `backend.tf` — local backend; state path = `<repo>/.local-state/<path_relative_to_include()>/terraform.tfstate`.
- `stack_meta.tf` — a generated `stack_path` output whose value is `path_relative_to_include()`,
  proving the function is evaluated per-unit at Terragrunt parse time.

Inspect what would be generated without applying:

```bash
cd live/application
terragrunt init        # writes the generated files into .terragrunt-cache/...
find .terragrunt-cache -name '*.tf' | xargs -I{} sh -c 'echo "== {} =="; cat {}'
```

## The `//` in `terraform.source` (important gotcha)

`source = "${get_repo_root()}/modules//artifact"`

The `//` is the go-getter "subdir" separator. Terragrunt copies everything **before** `//`
(the entire `modules/` dir) into its cache, then uses the subdir **after** `//` (`artifact`) as the
Terraform root. Without this, `modules/artifact`'s `module "labels" { source = "../labels" }` would
escape the copied tree and fail. If you ever split modules into their own repo, switch to a git source
like `git::https://.../modules.git//artifact?ref=v1.0.0`.

## Why artifacts and state are gitignored

Since Terramate v0.11, **untracked and uncommitted files count as changes**. If `local_file` wrote
artifacts into a tracked `live/*` directory, every stack would always look "changed" and the
change-detection demo would be meaningless. We write artifacts to `.artifacts/` and state to
`.local-state/`, both gitignored, so git diffs stay clean and change detection stays meaningful.

## CI integration

- **PR / plan** — `pr-preview` uses Terramate to build a parallel matrix of changed stacks +
  dependents, then calls `_plan-or-apply-env` per stack. Ordering is not required for plan because
  `mock_outputs` cover unapplied dependencies.
- **Merge / apply** — `deploy` uses a single `terramate run` so foundation → application →
  reporting order is preserved.
- **Drift** — `drift` runs `plan -detailed-exitcode` per stack and fails on drift. With the local
  backend, CI demonstrates the workflow shape but won't catch real drift until state is persisted
  remotely between runs.
- **Reconcile** — `reconcile` runs `terramate run --tags reconcile` (foundation + application only;
  reporting is deliberately excluded).

## Common commands

See [README.md](README.md#common-commands) for the full command reference and change-detection
verification walkthrough.

## Troubleshooting

- **Cycle detected / unexpected `after`:** units got nested. Keep `live/*` flat and re-run
  `terramate create --all-terragrunt`.
- **`dependency ... has no outputs`:** the upstream unit was never applied. Run a full
  `terramate run -- terragrunt apply` once, or rely on `mock_outputs` for plan/validate.
- **Every stack always "changed":** something writes into a tracked dir. Check `.gitignore`.
- **Flag not recognized (`--include-all-dependents`):** Terramate is too old — upgrade.
- **Module file changes don't trigger stacks:** Terragrunt function-based `source` paths can hide
  module changes from detection. For module-change triggering, use a plain relative source path
  (`source = "../../modules/artifact"`) — at the cost of losing the `//` copy trick, so you'd then
  need labels reachable another way. For this demo (which triggers on *live-unit* changes) it's a non-issue.
