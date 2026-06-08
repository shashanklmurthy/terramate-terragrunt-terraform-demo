# Addendum 2 — Drift & reconcile without Terramate Cloud

> Companion to `IMPLEMENTATION_PLAN.md` and `REUSABLE_WORKFLOWS_ADDENDUM.md`.
> **This replaces §4.3 (the `drift.yml`) of the reusable-workflows addendum.** No Terramate Cloud, no
> account, no SaaS — only the open-source CLI plus CI plumbing you already have.

## What this gives you (and the one honest caveat)

Terramate Cloud only provides the hosted *state + observability layer*: it remembers which stacks are
drifted, for how long, shows a dashboard, and sends alerts. All the *mechanics* — plan, exit codes,
tags, triggers, ordered apply — live in the OSS CLI. So Cloud-free, you replace three things yourself:
the **memory** of drift state, the **alerting**, and the **reconcile targeting** that Cloud's
`--status=drifted` filter gave you (that filter reads from Cloud, so it's unavailable here — you compute
the drifted set yourself).

**Caveat for THIS demo:** the local backend means Terraform state is **not persisted between CI runs**
(it lives in gitignored `.local-state/` on the runner and is thrown away). Drift detection only has
meaning against *persistent* state, so in CI these workflows demonstrate the correct *shape* but won't
catch real drift until you point the backend at a remote (S3/GCS/etc.) that survives between runs. To
see drift work today, run the detect loop **locally** after an `apply`, then simulate drift (delete a
file under `.artifacts/`, or hand-edit `.local-state/.../terraform.tfstate`) and re-run it.

---

## Step 1 — Tag the stacks you're willing to auto-reconcile

Reconciliation runs `apply`, which can be destructive, so you scope it with a tag rather than letting it
touch everything. Add `tags = ["reconcile"]` to the safe stacks. For the demo, tag `foundation` and
`application` and **deliberately leave `reporting` untagged** to show the scoping in action.

`live/foundation/stack.tm.hcl`:

```hcl
stack {
  name        = "foundation"
  description = "foundation"
  id          = "<uuid>"        # keep the generated id
  tags        = ["reconcile"]
}
```

`live/application/stack.tm.hcl`:

```hcl
stack {
  name        = "application"
  description = "application"
  id          = "<uuid>"
  after       = ["/live/foundation"]
  tags        = ["reconcile"]
}
```

`live/reporting/stack.tm.hcl` — **left untagged on purpose** (excluded from auto-reconcile):

```hcl
stack {
  name        = "reporting"
  description = "reporting"
  id          = "<uuid>"
  after       = ["/live/application"]
}
```

> Equivalent at creation time: `terramate create --all-terragrunt --tags reconcile` tags everything;
> here we want a subset, so edit the two files. Verify with `terramate list --tags reconcile` →
> should print `live/foundation` and `live/application` only.

---

## Step 2 — `drift.yml` (Cloud-free detect + alert)

Runs `plan -detailed-exitcode` per stack, classifies each (0 = clean, 2 = drift, other = error), writes
a report to the run summary, and fails the run on drift so GitHub's normal failed-run notifications fire.

`.github/workflows/drift.yml`:

```yaml
name: drift
on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch: {}

permissions:
  contents: read
  issues: write # only needed if you enable the open-issue step

jobs:
  detect:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4 # TODO(agent): pin SHA
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

      - name: Detect drift
        id: detect
        run: |
          drifted=()
          errored=()
          for stack in $(terramate list); do
            code=0
            ( cd "$stack" \
                && terragrunt init -input=false >/dev/null \
                && terragrunt plan -detailed-exitcode -lock=false -input=false >/dev/null ) || code=$?
            case "$code" in
              0) : ;;                     # no changes
              2) drifted+=("$stack") ;;   # drift detected
              *) errored+=("$stack") ;;   # plan error
            esac
          done
          {
            echo "## Drift report"
            echo ""
            echo "| state | stacks |"
            echo "|-------|--------|"
            echo "| drifted | ${drifted[*]:-none} |"
            echo "| errored | ${errored[*]:-none} |"
          } >> "$GITHUB_STEP_SUMMARY"
          echo "drifted=${drifted[*]:-}" >> "$GITHUB_OUTPUT"
          echo "count=${#drifted[@]}"   >> "$GITHUB_OUTPUT"

      # OPTIONAL: open/refresh a GitHub issue per drift run (uses the preinstalled gh CLI).
      # - name: Open drift issue
      #   if: steps.detect.outputs.count != '0'
      #   env:
      #     GH_TOKEN: ${{ github.token }}
      #   run: |
      #     gh issue create --title "Drift detected: ${{ steps.detect.outputs.drifted }}" \
      #       --body "Drift found on $(date -u). Stacks: ${{ steps.detect.outputs.drifted }}"

      # OPTIONAL: Slack webhook
      # - name: Notify Slack
      #   if: steps.detect.outputs.count != '0'
      #   run: |
      #     curl -fsSL -X POST -H 'Content-type: application/json' \
      #       --data "{\"text\":\"Drift: ${{ steps.detect.outputs.drifted }}\"}" \
      #       "${{ secrets.SLACK_WEBHOOK_URL }}"

      - name: Fail run if drift found
        if: steps.detect.outputs.count != '0'
        run: |
          echo "Drift detected in: ${{ steps.detect.outputs.drifted }}"
          exit 1
```

> Per-stack `terragrunt plan` here runs without Terramate ordering — fine for detection, since each plan
> is independent and unapplied dependencies are covered by the `mock_outputs` already in the units.

---

## Step 3 — `reconcile.yml` (tag-scoped, ordered apply)

The simplest Cloud-free reconcile: on a schedule, re-assert desired state on the `reconcile`-tagged
stacks. It doesn't even consult the detect job — applying idempotent stacks is a no-op when there's no
drift. `terramate run` keeps the apply in dependency order (foundation → application); `reporting` is
skipped because it isn't tagged.

`.github/workflows/reconcile.yml`:

```yaml
name: reconcile
on:
  schedule:
    - cron: "30 6 * * *" # after drift detection
  workflow_dispatch: {}

jobs:
  reconcile:
    runs-on: ubuntu-latest
    environment: dev # optional protected-Environment reviewer gate
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
      - name: Reconcile tagged stacks (apply, in dependency order)
        run: terramate run --tags reconcile -- terragrunt apply -auto-approve -lock=false -input=false
```

---

## Variant — reconcile through a reviewed PR instead of auto-apply

If you'd rather not auto-apply, turn drift into a normal change-detection PR. In the detect job, mark the
drifted stacks as changed with a trigger and open a PR; your existing `deploy.yml` then reconciles them
with review (and the audit trail lives in git, not a SaaS):

```bash
for s in ${{ steps.detect.outputs.drifted }}; do
  terramate trigger "$s"
done
git add .tmtriggers
git commit -m "chore: trigger drifted stacks for reconciliation"
gh pr create --fill --base main --head "drift/reconcile-$(date +%s)"
```

A committed `.tmtriggers` entry makes Terramate treat that stack as changed even though its code didn't
change, so the deploy picks it up.

---

## Making it real later

To get genuine drift detection in CI, swap the local backend in `root.hcl` for a persistent remote so
state survives between runs:

```hcl
remote_state {
  backend  = "s3" # or "gcs", "azurerm", ...
  generate = { path = "backend.tf", if_exists = "overwrite" }
  config = {
    bucket = "<your-state-bucket>"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = "<region>"
    # ...lock table / encryption as appropriate
  }
}
```

Everything in this addendum then works unchanged. The only thing you still won't have without Terramate
Cloud is the hosted *history/dashboard/alert-routing* — which Steps 2's summary + issue/Slack hooks and
your own metrics pipeline (Prometheus/CloudWatch/Datadog) cover at whatever fidelity you need.

## Summary of the trade

| Capability | Terramate Cloud | This addendum (Cloud-free) |
|---|---|---|
| Detect drift | scheduled sync | scheduled `plan -detailed-exitcode` loop |
| Remember drift state + duration | hosted dashboard | run summary / issue / your metrics store |
| Alert | built-in + Slack routing | failed run notifications / Slack webhook step |
| Target drifted stacks for reconcile | `--status=drifted` filter | compute the set yourself, or reconcile by `--tags reconcile` |
| Bound blast radius | `reconcile` tag | same `reconcile` tag |
| Reconcile in order | `terramate run` | `terramate run` (identical) |
```
