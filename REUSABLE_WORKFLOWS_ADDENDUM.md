# Addendum — Reusable workflows × Terramate

> Companion to `IMPLEMENTATION_PLAN.md`. **This replaces §9 of that plan.** It carries your
> `tf-reusable-workflows` layering into the demo and shows exactly where Terramate plugs into it.
> Still fully local (no AWS / OIDC).

---

## 1. How your existing pipeline maps onto Terramate

Your nine reusable workflows fall into two buckets once Terramate is in the picture.

| Your workflow | Role | With Terramate | Action |
|---|---|---|---|
| `_terraform-fmt` | leaf gate: `terraform fmt -check` | orchestration-agnostic | **carry over** |
| `_terragrunt-hclfmt` | leaf gate: hcl fmt check | orchestration-agnostic | **carry over** |
| `_checkov` | leaf gate: static scan | orchestration-agnostic | **carry over** |
| `_infracost` | leaf gate: cost diff | needs cloud cost data | **omit** (no cost on local providers) |
| `_plan-or-apply-env` | core engine: init→validate→plan→apply for **one** dir | reused **unchanged** as the per-dir engine | **carry over** (drop only the OIDC step) |
| `_main-deploy-to-env` | wrapper: calls core with `apply=true` | superseded by the deploy entrypoint | **fold into entrypoint** |
| `_release-deploy-to-test-and-prod` | test→prod promotion w/ env gate | orthogonal to Terramate | **keep pattern** (env gate preserved via `environment:`) |
| `_pr-to-main` | single-dir PR orchestrator | superseded | drop |
| `_pr-to-main-multiple-folders` | **static matrix** from `terragrunt-working-dirs.yaml` | **this is what Terramate replaces** | **replace `create-matrix` with `terramate list --changed`** |

**The headline:** your `create-matrix` job reads a hand-maintained `.gp/terragrunt-working-dirs.yaml`
and fans out a job per directory, in parallel, with **no change detection and no ordering**. Terramate
replaces that single job — `terramate list --changed --include-all-dependents` produces the matrix
dynamically from what actually changed and knows the dependency order. Everything *below* the matrix
(your `_plan-or-apply-env` engine and the leaf gates) is reused as-is.

### The one tension to design around: matrix parallelism vs. ordering

A GitHub Actions matrix runs entries in parallel — it cannot enforce foundation-before-application. So:

- **PR / plan →** Terramate-generated **matrix** calling `_plan-or-apply-env` is great: parallel,
  per-dir isolation, per-dir comments. Unapplied dependencies are covered by `mock_outputs`.
- **merge / apply →** use the **single-job** form `terramate run --changed -- terragrunt apply`, so
  ordering (foundation→application→reporting) is preserved. (A matrix would apply them in the wrong order.)

Both patterns appear below.

---

## 2. Leaf reusable workflows (carry over)

### 2.1 `.github/workflows/_terraform-fmt.yml`

```yaml
# Mirrors gp-nova _terraform-fmt (local demo: no private-module git config, no OIDC).
name: _terraform-fmt
on:
  workflow_call:
    inputs:
      working-dir:
        type: string
        default: "modules"

jobs:
  fmt-check:
    runs-on: ubuntu-latest
    name: terraform fmt ${{ inputs.working-dir }}
    steps:
      - uses: actions/checkout@v4 # TODO(agent): pin SHA
      - uses: hashicorp/setup-terraform@v3 # TODO(agent): pin
        with:
          terraform_version: "1.11.4"
          terraform_wrapper: false
      - run: terraform fmt -check -recursive ${{ inputs.working-dir }}
```

### 2.2 `.github/workflows/_terragrunt-hclfmt.yml`

```yaml
# Mirrors gp-nova _terragrunt-hclfmt.
name: _terragrunt-hclfmt
on:
  workflow_call: {}

jobs:
  hclfmt-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Terragrunt
        run: |
          curl -fsSL -o /usr/local/bin/terragrunt \
            "https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.22/terragrunt_linux_amd64"
          chmod +x /usr/local/bin/terragrunt
      # Terragrunt >= ~0.73 uses the redesigned CLI: `terragrunt hcl fmt --check`.
      # Pre-0.73 used `terragrunt hclfmt --terragrunt-check`. Match your pinned version.
      - run: terragrunt hcl fmt --check
```

### 2.3 `.github/workflows/_checkov.yml`

```yaml
# Mirrors gp-nova _checkov. Scans the Terraform modules (the live/ dirs are pure Terragrunt HCL).
name: _checkov
on:
  workflow_call:
    inputs:
      directory:
        type: string
        default: "modules"

jobs:
  checkov:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bridgecrewio/checkov-action@v12 # TODO(agent): pin
        with:
          directory: ${{ inputs.directory }}
          framework: terraform
          soft_fail: true # demo modules use only random/local; keep as gate, don't block
```

> In your real repo this is also where `_infracost` would sit. It's omitted here because local
> providers have no cloud cost to estimate.

---

## 3. Core engine (carry over — drop only the OIDC step)

### 3.1 `.github/workflows/_plan-or-apply-env.yml`

```yaml
# Faithful to gp-nova _plan-or-apply-env: same input contract (environment, working-dir, apply,
# lock, version-files) and the plan-comment behavior. The ONLY omission vs the org version is the
# OIDC role-assumption step — local providers need no cloud auth. The `environment:` key is kept so
# a protected GitHub Environment can act as the reviewer gate, exactly as in the org pipeline.
name: _plan-or-apply-env
on:
  workflow_call:
    inputs:
      environment:
        type: string
        default: dev
      working-dir:
        required: true
        type: string
      apply:
        type: boolean
        default: false
      lock:
        type: boolean
        default: true
      terraform-version-file:
        type: string
        default: ".terraform-version"
      terragrunt-version-file:
        type: string
        default: ".terragrunt-version"

jobs:
  terragrunt:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }} # reviewer/secret gate, same as org pattern
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Resolve tool versions
        id: versions
        run: |
          echo "tf=$(cat ${{ inputs.terraform-version-file }})" >> "$GITHUB_OUTPUT"
          echo "tg=$(cat ${{ inputs.terragrunt-version-file }})" >> "$GITHUB_OUTPUT"

      - uses: hashicorp/setup-terraform@v3 # TODO(agent): pin
        with:
          terraform_version: ${{ steps.versions.outputs.tf }}
          terraform_wrapper: false

      - name: Setup Terragrunt
        run: |
          curl -fsSL -o /usr/local/bin/terragrunt \
            "https://github.com/gruntwork-io/terragrunt/releases/download/v${{ steps.versions.outputs.tg }}/terragrunt_linux_amd64"
          chmod +x /usr/local/bin/terragrunt

      # --- ORG VERSION: the OIDC role-assumption step goes HERE ------------------------
      #   - uses: gp-nova/devx-action-assume-oidc-role@v2
      #     with: { config-location: .gp/roles.yaml, environment: ${{ inputs.environment }} }
      #   The local demo skips it (local backend, no cloud).
      # ---------------------------------------------------------------------------------

      - name: Terragrunt init
        working-directory: ${{ inputs.working-dir }}
        run: terragrunt init -input=false

      - name: Terragrunt validate
        if: ${{ inputs.apply != true }}
        working-directory: ${{ inputs.working-dir }}
        run: terragrunt validate

      - name: Terragrunt plan
        id: plan
        working-directory: ${{ inputs.working-dir }}
        run: terragrunt plan -out workspace.plan -lock=${{ inputs.lock }} -input=false

      - name: Post plan (job summary)
        if: always()
        working-directory: ${{ inputs.working-dir }}
        run: |
          {
            echo "### Plan — \`${{ inputs.working-dir }}\` (${{ inputs.environment }})"
            echo '```'
            terragrunt show -no-color workspace.plan 2>/dev/null || echo "(no plan)"
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"
        # ORG VERSION: gp-nova/terraform-pr-commenter@v1.0.1 posts this to the PR instead.

      - name: Terragrunt apply
        if: ${{ inputs.apply == true }}
        working-directory: ${{ inputs.working-dir }}
        run: terragrunt apply -auto-approve -input=false
```

---

## 4. Entrypoints — the two integration patterns

### 4.1 Pattern A (PR / plan): Terramate-generated matrix → your engine

This is the **direct replacement** for `_pr-to-main-multiple-folders`'s `create-matrix` job. Instead of
reading `.gp/terragrunt-working-dirs.yaml`, the `set-matrix` job asks Terramate which stacks changed.

`.github/workflows/pr-preview.yml`:

```yaml
name: pr-preview
on:
  pull_request:
    branches: [main]

jobs:
  fmt:
    uses: ./.github/workflows/_terraform-fmt.yml
  hclfmt:
    uses: ./.github/workflows/_terragrunt-hclfmt.yml
  checkov:
    uses: ./.github/workflows/_checkov.yml

  # Replaces the static create-matrix job. Terramate emits the changed stacks (+ their
  # transitive dependents) as the matrix.
  set-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.tm.outputs.matrix }}
      has_changes: ${{ steps.tm.outputs.has_changes }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: terramate-io/terramate-action@v2 # TODO(agent): confirm
      - id: tm
        run: |
          mapfile -t dirs < <(terramate list --changed --include-all-dependents \
            --git-change-base "origin/${{ github.base_ref }}" --run-order)
          if [ "${#dirs[@]}" -eq 0 ]; then
            echo "has_changes=false" >> "$GITHUB_OUTPUT"
            echo 'matrix={"working-dir":[]}' >> "$GITHUB_OUTPUT"
          else
            json="$(printf '%s\n' "${dirs[@]}" | jq -R . | jq -cs .)"
            echo "has_changes=true" >> "$GITHUB_OUTPUT"
            echo "matrix={\"working-dir\":${json}}" >> "$GITHUB_OUTPUT"
          fi

  plan:
    needs: set-matrix
    if: needs.set-matrix.outputs.has_changes == 'true'
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.set-matrix.outputs.matrix) }}
    uses: ./.github/workflows/_plan-or-apply-env.yml
    with:
      working-dir: ${{ matrix.working-dir }}
      environment: dev
      apply: false
```

> `terramate list` prints repo-relative paths (`live/foundation`, ...), which is exactly the
> `working-dir` your engine expects. On a PR touching nothing, `has_changes=false` skips the plan job.
> Ordering is **not** preserved here (parallel matrix) — that's fine for plan because `mock_outputs`
> stand in for unapplied dependencies.

### 4.2 Pattern B (merge / apply): single ordered Terramate run

For apply, ordering matters, so do **not** use a matrix. One job, Terramate handles the order.

`.github/workflows/deploy.yml`:

```yaml
name: deploy
on:
  push:
    branches: [main]

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: dev # reviewer gate, same as org pattern
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: hashicorp/setup-terraform@v3 # TODO(agent): pin
        with:
          terraform_version: "1.11.4"
          terraform_wrapper: false
      - name: Setup Terragrunt
        run: |
          curl -fsSL -o /usr/local/bin/terragrunt \
            "https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.22/terragrunt_linux_amd64"
          chmod +x /usr/local/bin/terragrunt
      - uses: terramate-io/terramate-action@v2 # TODO(agent): confirm
      - name: Apply changed stacks, in dependency order
        run: |
          terramate run --changed --include-all-dependents \
            --git-change-base "HEAD^" -- \
            terragrunt apply -auto-approve -input=false
```

### 4.3 Drift (scheduled): all stacks, plan-only

Mirrors your `drift-detection.yaml`, but runs every stack via Terramate instead of the static matrix.

`.github/workflows/drift.yml`:

```yaml
name: drift
on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch: {}

jobs:
  drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.11.4"
          terraform_wrapper: false
      - name: Setup Terragrunt
        run: |
          curl -fsSL -o /usr/local/bin/terragrunt \
            "https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.22/terragrunt_linux_amd64"
          chmod +x /usr/local/bin/terragrunt
      - uses: terramate-io/terramate-action@v2
      - name: Plan all stacks (detect drift)
        run: terramate run -- terragrunt plan -detailed-exitcode -lock=false -input=false
```

### 4.4 Release promotion (optional — keep your pattern)

`_release-deploy-to-test-and-prod` stays valuable and orthogonal: its job is the **test→prod gate via
protected GitHub Environments**, which Terramate doesn't replace. To Terramate-enable it, give each
stage the same single-job body as Pattern B but with `environment: test` then `environment: prod`
(`needs: [test]`). The reviewer gate is the protected `prod` Environment, exactly as today.

---

## 5. What changed vs. the original plan §9

- `_fmt-and-validate.yml` (a single combined gate) is **superseded** by the three faithful leaf
  workflows `_terraform-fmt` / `_terragrunt-hclfmt` / `_checkov`, matching your real layering.
- `_terramate-orchestrate.yml` is **split into the two honest patterns**: Pattern A (matrix → your
  `_plan-or-apply-env`) for plan, Pattern B (single `terramate run`) for apply.
- `_plan-or-apply-env.yml` is **added** as the reused core engine.

## 6. Branch protection

Require the **entrypoints only** — `pr-preview` and its child jobs (`fmt`, `hclfmt`, `checkov`,
`plan`). Never require the `_`-prefixed reusable workflows; they have no triggers of their own. Same
rule as your org template.

## 7. Talking points for the demo (the interplay, in one breath)

- Leaf gates and the per-dir engine are **unchanged** — reusable workflows compose with Terramate, not
  against it.
- Terramate **replaces exactly one thing**: the static `terragrunt-working-dirs.yaml` + `create-matrix`
  fan-out, swapping "run every listed dir, in parallel, always" for "run the dirs that changed and
  everything that depends on them, in the right order."
- Plan uses Terramate to **build the matrix**; apply uses Terramate to **run in order**. That split is
  the whole point.
```
