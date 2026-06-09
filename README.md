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
modules/artifact  (layered: labels + random_string)
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

Each chained shared unit exposes a `summary` output (`id`, `token`, `artifact_path`, `tags`,
`contract_version`) consumed by downstream `dependency` blocks, plus an `upstream_chain` list output that
echoes the full upstream chain (nearest dependency first). The `random_string.token` resource re-rolls when `contract_version`
changes (via `keepers`) so propagation can surface in the **resource** section of plans — but
only once a stack's **applied** upstream state is ahead of what that stack last recorded (see
[PR vs deploy expectations](#pr-vs-deploy-expectations) below).
Committed JSON under `baseline/.artifacts/` is a frozen demo snapshot only.

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

### Propagate platform values through the chain

Platform sets `contract_version` locally (e.g. `"2024-06"`). Downstream stacks prepend each
dependency's summary to the front of an `upstream` list; the module takes the **last** entry's
`contract_version` when upstream is non-empty, otherwise falls back to the local input (platform
root only):

```
platform.summary  →  app-layer upstream: [platform]
                 →  analytics upstream: [app_layer, platform]   # concat at each layer
                              ↓ upstream_chain output (same list, passed through)
```

Terragrunt wiring (analytics example):

```hcl
upstream = concat(
  [dependency.app_layer.outputs.summary],
  dependency.app_layer.outputs.upstream_chain,
)
```

Terragrunt `dependency` blocks read **applied upstream state**, not pending code changes from a
sibling stack's plan. That is why propagation is **staged**: each layer picks up new values only
after the upstream stack has been applied.

#### PR vs deploy expectations

This demo intentionally does **not** apply upstream stacks during PR preview — no per-PR sandboxes,
no sequential apply-before-review in CI. PR plans are an honest partial view; full propagation
shows up after **ordered apply on merge** (`deploy` workflow).

| Phase | What to look for |
|-------|------------------|
| **PR plan (`pr-preview`)** | Terramate lists `platform`, `app-layer`, and `analytics`. **Platform** is the headline: `~ contract_version` + `-/+ random_string.token`. Downstream stacks may show output drift (`~ upstream_chain`, `~ summary.contract_version`) or partial token changes against **baseline** upstream state — not the full pending version from the PR code. |
| **Deploy (merge to `main`)** | `deploy` applies in dependency order. Each stack reads freshly applied upstream outputs; token keepers re-roll stack by stack until the chain is in sync. |
| **After full apply** | Plans are clean. Re-seed `baseline/` if you want the next PR demo to start from this snapshot. |

**Example PR** (baseline seeded, code bumps `contract_version` to `"2025-01"` while baseline state
still has `"2024-06"`):

- `platform` — `~ contract_version` on summary and `-/+ random_string.token`
- `app-layer` — may show `~ upstream_chain` / `~ summary.contract_version` and sometimes
  `-/+ random_string.token` for drift vs **applied** baseline upstream (`null → 2024-06`), not
  `→ 2025-01` until platform is applied on merge
- `analytics` — often quiet on resources until app-layer has been applied with a new
  `contract_version`

**Walk through full propagation locally** (after seeding baseline):

```bash
terramate run live/shared/us-east-1/dev/platform -- terragrunt apply -auto-approve -input=false
terramate run live/shared/us-east-1/dev/app-layer -- terragrunt plan -input=false   # now sees applied version
terramate run live/shared/us-east-1/dev/app-layer -- terragrunt apply -auto-approve -input=false
terramate run live/shared/us-east-1/dev/analytics -- terragrunt plan -input=false
```

Or apply the whole changed chain in one go (same as `deploy`):

```bash
terramate run --include-all-dependents live/shared/us-east-1/dev/platform -- \
  terragrunt apply -auto-approve -input=false
```

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
`terraform-pr-commenter` may post **two comments per stack** (resource plan + `Changes to Outputs:`).

Read the comments with staged propagation in mind: **platform** shows the intended change; **app-layer**
and **analytics** comments mean "these stacks are in Terramate's blast radius and will reconcile
on deploy," not "full upstream values already visible in this plan." A `contract_version` bump on
platform should show **`~ contract_version`** and token re-roll, not `+ create` for artifact files.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `git-out-of-sync` / unable to reach `origin/main` in CI | PR branches are not rebased on `main`; CI sets `TM_DISABLE_SAFEGUARDS=git-out-of-sync`. Locally: `git fetch origin main && git rebase origin/main` |
| `Error: repository has untracked files` | Commit or stash; Terramate refuses to run with dirty git |
| `dependency ... has no outputs` | Run full apply once, or rely on `mock_outputs` for plan |
| Every stack always "changed" | Something writes into a tracked dir — check `.gitignore` |
| `--include-all-dependents` not recognized | Upgrade Terramate (needs 2024+ build) |
