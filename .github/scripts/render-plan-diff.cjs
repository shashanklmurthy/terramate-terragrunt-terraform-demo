// Render a Terraform plan file as a git-diff-style text summary.
// Usage: node render-plan-diff.cjs <stack> <plan-file> [repo-root]

const { execSync } = require("node:child_process");
const path = require("node:path");

const TG_ENV = { TG_TF_FORWARD_STDOUT: "true" };

function loadPlanJson(planFile, stackDir) {
  const raw = execSync(`terragrunt show -json "${planFile}"`, {
    cwd: stackDir,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
    env: { ...process.env, ...TG_ENV },
  });
  return JSON.parse(raw);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function formatScalar(value) {
  if (value === null) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  return String(value);
}

function walkAttributes(prefix, value, unknown, sign, lines) {
  if (unknown === true) {
    lines.push(`${sign}${prefix}(known after apply)`);
    return;
  }
  if (Array.isArray(value)) {
    if (value.length === 0) {
      lines.push(`${sign}${prefix}[]`);
      return;
    }
    for (const item of value) {
      walkAttributes(`${prefix}  `, item, null, sign, lines);
    }
    return;
  }
  if (isObject(value)) {
    if (Object.keys(value).length === 0) {
      lines.push(`${sign}${prefix}{}`);
      return;
    }
    for (const [k, v] of Object.entries(value).sort()) {
      walkAttributes(`${prefix}${k}.`, v, unknown?.[k], sign, lines);
    }
    return;
  }
  lines.push(`${sign}${prefix}${formatScalar(value)}`);
}

function emitAttributes(attrs, unknown, sign, lines, indent = "  ") {
  for (const [k, v] of Object.entries(attrs ?? {}).sort()) {
    if (unknown?.[k] === true) {
      lines.push(`${sign}${indent}${k} = (known after apply)`);
      continue;
    }
    if (isObject(v) && !Array.isArray(v)) {
      lines.push(`${sign}${indent}${k} = {`);
      for (const [sk, sv] of Object.entries(v).sort()) {
        if (unknown?.[k]?.[sk] === true) {
          lines.push(`${sign}${indent}  ${sk} = (known after apply)`);
        } else {
          lines.push(`${sign}${indent}  ${sk} = ${formatScalar(sv)}`);
        }
      }
      lines.push(`${sign}${indent}}`);
    } else if (Array.isArray(v)) {
      lines.push(`${sign}${indent}${k} = ${formatScalar(v)}`);
    } else {
      lines.push(`${sign}${indent}${k} = ${formatScalar(v)}`);
    }
  }
}

function actionLabel(actions) {
  const set = new Set(actions);
  if (set.has("delete") && set.has("create")) return "replace";
  return actions.filter((a) => a !== "no-op").join("/") || "no-op";
}

function formatResourceChange(rc) {
  const actions = rc.change.actions.filter((a) => a !== "no-op");
  if (actions.length === 0) return [];

  const label = actionLabel(rc.change.actions);
  const lines = [`@@ ${rc.address} [${label}] @@`];
  const set = new Set(rc.change.actions);

  if (set.has("delete") && set.has("create")) {
    lines.push(`- resource "${rc.type}" "${rc.name}" {`);
    emitAttributes(rc.change.before, null, "-", lines);
    lines.push("- }");
    lines.push(`+ resource "${rc.type}" "${rc.name}" {`);
    emitAttributes(rc.change.after, rc.change.after_unknown, "+", lines);
    lines.push("+ }");
    return lines;
  }

  if (set.has("delete")) {
    lines.push(`- resource "${rc.type}" "${rc.name}" {`);
    emitAttributes(rc.change.before, null, "-", lines);
    lines.push("- }");
    return lines;
  }

  if (set.has("create")) {
    lines.push(`+ resource "${rc.type}" "${rc.name}" {`);
    emitAttributes(rc.change.after, rc.change.after_unknown, "+", lines);
    lines.push("+ }");
    return lines;
  }

  if (set.has("update")) {
    const before = rc.change.before ?? {};
    const after = rc.change.after ?? {};
    const unknown = rc.change.after_unknown ?? {};
    const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
    let any = false;
    for (const key of [...keys].sort()) {
      const b = before[key];
      const a = after[key];
      if (JSON.stringify(b) === JSON.stringify(a) && !unknown[key]) continue;
      any = true;
      if (unknown[key] === true) {
        lines.push(`-   ${key} = ${formatScalar(b)}`);
        lines.push(`+   ${key} = (known after apply)`);
      } else if (b === undefined) {
        lines.push(`+   ${key} = ${formatScalar(a)}`);
      } else if (a === undefined) {
        lines.push(`-   ${key} = ${formatScalar(b)}`);
      } else {
        lines.push(`-   ${key} = ${formatScalar(b)}`);
        lines.push(`+   ${key} = ${formatScalar(a)}`);
      }
    }
    return any ? lines : [];
  }

  return lines;
}

function formatOutputChange(oc) {
  const actions = oc.change.actions.filter((a) => a !== "no-op");
  if (actions.length === 0) return [];

  const lines = [`@@ output.${oc.name} [${actions.join("/")}] @@`];
  if (actions.includes("delete")) {
    lines.push(`- value = ${formatScalar(oc.change.before)}`);
  }
  if (actions.includes("create") || actions.includes("update")) {
    if (oc.change.after_unknown) {
      lines.push(`+ value = (known after apply)`);
    } else {
      lines.push(`+ value = ${formatScalar(oc.change.after)}`);
    }
  }
  return lines;
}

function countChanges(plan) {
  let add = 0;
  let change = 0;
  let destroy = 0;
  for (const rc of plan.resource_changes ?? []) {
    const set = new Set(rc.change.actions);
    if (set.has("delete") && set.has("create")) {
      add += 1;
      destroy += 1;
    } else if (set.has("create")) add += 1;
    else if (set.has("delete")) destroy += 1;
    else if (set.has("update")) change += 1;
  }
  return { add, change, destroy };
}

function renderPlanDiff(stack, planFile, stackDir) {
  const plan = loadPlanJson(planFile, stackDir);
  const lines = [`diff --plan ${stack}`, "--- state", "+++ plan", ""];

  for (const rc of plan.resource_changes ?? []) {
    const block = formatResourceChange(rc);
    if (block.length) lines.push(...block, "");
  }

  for (const oc of plan.output_changes ?? []) {
    const block = formatOutputChange(oc);
    if (block.length) lines.push(...block, "");
  }

  const { add, change, destroy } = countChanges(plan);
  if (add === 0 && change === 0 && destroy === 0) {
    lines.push("No changes. Infrastructure is up-to-date.");
  } else {
    lines.push(`Plan: ${add} to add, ${change} to change, ${destroy} to destroy.`);
  }

  return lines.join("\n").trimEnd();
}

module.exports = { renderPlanDiff };

if (require.main === module) {
  const stack = process.argv[2];
  const planFile = process.argv[3];
  const repoRoot = process.argv[4] || process.env.GITHUB_WORKSPACE || process.cwd();
  const stackDir = path.join(repoRoot, stack);
  if (!stack || !planFile) {
    console.error("usage: node render-plan-diff.cjs <stack> <plan-file> [repo-root]");
    process.exit(1);
  }
  process.stdout.write(renderPlanDiff(stack, planFile, stackDir));
}
