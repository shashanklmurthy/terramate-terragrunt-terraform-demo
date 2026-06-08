# terramate-terragrunt-terraform-demo

A minimal, **fully local** (no cloud) reference showing **Terraform + Terragrunt + Terramate**
working together, structured like the official
[terramate-terragrunt-infrastructure-live-example](https://github.com/terramate-io/terramate-terragrunt-infrastructure-live-example)
with all deployable units under `live/`:

- **Terraform** defines reusable modules in `modules/`.
- **Terragrunt** defines deployable units in `live/` with `live/_envcommon/`, `account.hcl`,
  `region.hcl`, and `env.hcl` metadata baked in from parent folders.
- **Terramate** orchestrates change detection and runs stacks — plus transitive dependents — in order.

Providers used: `hashicorp/random` and `hashicorp/local`. No credentials, no remote state.

## Architecture

```
modules/labels    (leaf: naming + tags, no resources)
        ▲
        │ used by
        │
modules/artifact  (layered: labels + random_string + local_file)
        ▲
        │ sourced by every deployable unit via live/_envcommon/
        │
┌─────────────────────────────────────────────────────────────────────────┐
│ live/shared/  (multi-tenant platform — one chain, shared by all users) │
│   account.hcl → us-east-1/region.hcl → dev/env.hcl                    │
│     platform ──▶ app-layer ──▶ analytics                              │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│ live/dedicated/  (single-tenant — one isolated instance per tenant)      │
│   acme/account.hcl → us-east-1/region.hcl → dev/tenant-instance         │
│   initech/account.hcl → us-east-1/region.hcl → dev/tenant-instance      │
│   (no dependency on the shared platform chain)                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Two tenancy realities

| Model | Path | Analogy | Dependency chain |
|-------|------|---------|------------------|
| **Multi-tenant shared** | `live/shared/us-east-1/dev/*` | Shared platform brought up once for all tenants | `platform` → `app-layer` → `analytics` |
| **Single-tenant dedicated** | `live/dedicated/<tenant>/us-east-1/dev/tenant-instance` | One Terragrunt module = one tenant instance | None (isolated per tenant) |

Each chained shared unit produces a JSON artifact in `.artifacts/` and exposes a `summary` output.
The next layer consumes that summary through a Terragrunt `dependency` block.

Dedicated tenant instances embed `tenant_id` in resource IDs (e.g. `demo-acme-dev-tenant-instance`)
and tags, but do not depend on the shared chain.

## Directory layout

```
.
├── root.hcl                         # Global Terragrunt: backend, generate, merged inputs
├── terramate.tm.hcl                 # Terramate project config
└── live/
    ├── _envcommon/                  # DRY component configs (shared across units)
    │   ├── platform.hcl
    │   ├── app-layer.hcl
    │   ├── analytics.hcl
    │   └── tenant-instance.hcl
    ├── shared/                      # Multi-tenant account
    │   ├── account.hcl
    │   └── us-east-1/
    │       ├── region.hcl
    │       └── dev/
    │           ├── env.hcl
    │           ├── platform/
    │           ├── app-layer/
    │           └── analytics/
    └── dedicated/                   # Single-tenant accounts
        ├── acme/
        │   ├── account.hcl
        │   └── us-east-1/dev/tenant-instance/
        └── initech/
            ├── account.hcl
            └── us-east-1/dev/tenant-instance/
```

Every leaf component directory contains `terragrunt.hcl` + `stack.tm.hcl`.

### Metadata flow (like the official example)

```
live/shared/us-east-1/dev/platform/terragrunt.hcl
  └─ include root.hcl
       ├─ find account.hcl  → live/shared/account.hcl           (tenancy, project)
       ├─ find region.hcl   → live/shared/us-east-1/region.hcl
       └─ find env.hcl      → live/shared/us-east-1/dev/env.hcl
  └─ include live/_envcommon/platform.hcl                       (module source, component inputs)
```

`root.hcl` merges `account.hcl` + `region.hcl` + `env.hcl` locals into `inputs` for every child.

## Mental model

| Tool | Owns | Unit of work |
|------|------|--------------|
| Terraform | Resource definitions | a *module* (`modules/*`) |
| Terragrunt | Per-environment wiring, DRY config, dependencies | a *unit* (`live/*/terragrunt.hcl`) |
| Terramate | Change detection + orchestration across units | a *stack* (`live/*/stack.tm.hcl`) |

A Terragrunt **unit** and a Terramate **stack** are the same directory.

`dependency` blocks do two things at once:
- **Runtime:** Terragrunt fetches upstream outputs (`mock_outputs` cover plan-before-apply).
- **Orchestration:** Terramate parses them to set `after` ordering and compute dependents.

## Prerequisites

All versions are pinned in [`.tool-versions`](.tool-versions).

| Tool | Local install |
|------|---------------|
| Terraform | [tfenv](https://github.com/tfutils/tfenv) |
| Terragrunt | [tgenv](https://github.com/cunymatthieu/tgenv) |
| Terramate | e.g. `brew install terramate` |

CI installs all three from `.tool-versions` via [`.github/actions/setup-asdf`](.github/actions/setup-asdf).

## First-time bootstrap

Terramate requires a clean git working tree (commit or stash changes first).

```bash
# Init and apply everything, in dependency order
terramate run -- terragrunt init -input=false
terramate run -- terragrunt apply -auto-approve -input=false
```

Verify:

```bash
terramate list --run-order
# live/shared/us-east-1/dev/platform
# live/dedicated/acme/us-east-1/dev/tenant-instance
# live/dedicated/initech/us-east-1/dev/tenant-instance
# live/shared/us-east-1/dev/app-layer
# live/shared/us-east-1/dev/analytics

ls .artifacts/
# demo-dev-platform.json, demo-dev-app-layer.json, demo-dev-analytics.json
# demo-acme-dev-tenant-instance.json, demo-initech-dev-tenant-instance.json
```

## Change detection and ordering

```bash
terramate run --changed --include-all-dependents -- terragrunt apply -auto-approve
```

In CI, add `--git-change-base origin/main` (PRs) or `HEAD^` (push to main).

### Verify transitive change detection

**Case 1 — change only `platform`:**

```bash
git switch -c demo/change-platform
# edit live/shared/us-east-1/dev/platform/terragrunt.hcl, commit
terramate list --changed --include-all-dependents --git-change-base main --run-order
# expected: platform, app-layer, analytics
# (dedicated tenant instances are NOT included)
```

**Case 2 — change only `app-layer`:**

```bash
# edit live/shared/us-east-1/dev/app-layer/terragrunt.hcl, commit
terramate list --changed --include-all-dependents --git-change-base main --run-order
# expected: app-layer, analytics  (NOT platform)
```

**Case 3 — change a dedicated tenant instance:**

```bash
# edit live/dedicated/acme/us-east-1/dev/tenant-instance/terragrunt.hcl, commit
terramate list --changed --include-all-dependents --git-change-base main --run-order
# expected: only acme tenant-instance (isolated from shared chain)
```

## Common commands

```bash
terramate list --run-order
terramate list --tags reconcile                              # platform + app-layer
terramate list --tags tenancy-single-tenant                  # dedicated tenant instances
terramate run -- terragrunt plan -input=false
terramate run --tags reconcile -- terragrunt apply -auto-approve -input=false
```

### Format checks

```bash
terraform fmt -check -recursive modules/
terramate run -- terragrunt hcl fmt --check
```

### Pre-commit hooks

```bash
pre-commit install
pre-commit run --all-files
```

Hooks run `.github/hooks/fmt.sh` (see [pre-commit.com](https://pre-commit.com/#install)).

## Generated files (`root.hcl`)

Generated files land in the **Terragrunt cache** working directory:

- `versions.tf`, `provider.tf`, `backend.tf`
- `stack_meta.tf` — `stack_path` + `stack_metadata` outputs from parent metadata

State path: `<repo>/.local-state/<path_relative_to_include()>/terraform.tfstate`

## Demo baseline (local + remote PR)

Applied state and artifacts live under **`baseline/`** (committed). Runtime paths
`.local-state/` and `.artifacts/` are gitignored.

**Local demo** — seed before plan:

```bash
cp -R baseline/.local-state .local-state
cp -R baseline/.artifacts .artifacts
terramate run --changed --include-all-dependents --git-change-base main -- terragrunt plan -input=false
```

**Remote PR demo** — two steps:

1. Merge a **bootstrap PR** that adds `baseline/` (current applied state) to `main`.
2. Open a **demo PR** that edits e.g. `live/shared/us-east-1/dev/platform/terragrunt.hcl`.

`pr-preview` seeds `baseline/` into runtime paths, runs `terramate list --changed
--git-change-base origin/main`, and posts incremental plan comments on the PR.

To refresh the baseline after re-applying locally: update files under `baseline/` and commit.

## CI workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `pr-preview` | PR → `main` | fmt + hclfmt + validate + checkov; plan changed stacks; PR comments |
| `deploy` | push → `main` | apply changed + dependents |
| `drift` | daily cron | plan `-detailed-exitcode` on every stack |
| `reconcile` | daily cron | apply `--tags reconcile` stacks |

**PR comments:** Plan output is captured per changed stack (e.g. `live-shared-us-east-1-dev-platform.txt`)
and posted with `TF_WORKSPACE` set to the stack path (e.g. `live/shared/us-east-1/dev/platform`).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Error: repository has untracked files` | Commit or stash; Terramate refuses to run with dirty git |
| `dependency ... has no outputs` | Run full apply once, or rely on `mock_outputs` for plan |
| Every stack always "changed" | Something writes into a tracked dir — check `.gitignore` |
| `--include-all-dependents` not recognized | Upgrade Terramate (needs 2024+ build) |
