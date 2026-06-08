// Posts one sticky PR comment per Terramate stack (marocchino-compatible marker).
// Expects STACKS (newline-separated paths) and PLAN_FAILED (true|false) in the environment.

const { execSync } = require("node:child_process");
const path = require("node:path");

const MAX_PLAN_CHARS = 60_000;

module.exports = async ({ github, context, core }) => {
  const stacks = (process.env.STACKS ?? "")
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
  const planFailed = process.env.PLAN_FAILED === "true";
  const sha = context.payload.pull_request.head.sha;
  const issue_number = context.payload.pull_request.number;

  const headerFor = (stack) => `plan-${stack.replace(/\//g, "-")}`;
  const markerFor = (header) => `<!-- sticky-pull-request-comment:${header} -->`;

  async function listAllComments() {
    const comments = [];
    let page = 1;
    while (true) {
      const { data } = await github.rest.issues.listComments({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number,
        per_page: 100,
        page,
      });
      comments.push(...data);
      if (data.length < 100) break;
      page += 1;
    }
    return comments;
  }

  async function upsertComment(header, body) {
    const marker = markerFor(header);
    const fullBody = `${marker}\n${body}`;
    const comments = await listAllComments();
    const existing = comments.find((c) => c.body?.includes(marker));
    if (existing) {
      await github.rest.issues.updateComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        comment_id: existing.id,
        body: fullBody,
      });
    } else {
      await github.rest.issues.createComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number,
        body: fullBody,
      });
    }
  }

  async function deleteComment(header) {
    const marker = markerFor(header);
    const comments = await listAllComments();
    const existing = comments.find((c) => c.body?.includes(marker));
    if (existing) {
      await github.rest.issues.deleteComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        comment_id: existing.id,
      });
    }
  }

  let allStacks = [];
  try {
    allStacks = execSync("terramate list --run-order", { encoding: "utf8" })
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);
  } catch (error) {
    core.warning(`terramate list failed: ${error.message}`);
  }

  const changed = new Set(stacks);
  for (const stack of allStacks) {
    if (!changed.has(stack)) {
      await deleteComment(headerFor(stack));
    }
  }

  if (stacks.length === 0) {
    await upsertComment(
      "preview-summary",
      ["## Terragrunt preview", "", `Commit: \`${sha}\``, "", "No changed stacks in this PR."].join(
        "\n",
      ),
    );
    return;
  }

  const summaryLines = [
    "## Terragrunt preview",
    "",
    `Commit: \`${sha}\``,
    "",
    `**${stacks.length}** stack(s) in this preview — each plan is a separate comment below.`,
    "",
    ...stacks.map((s) => `- \`${s}\``),
  ];
  if (planFailed) {
    summaryLines.push(
      "",
      ":warning: One or more plans failed. See per-stack comments and the Actions log.",
    );
  }
  await upsertComment("preview-summary", summaryLines.join("\n"));

  for (const stack of stacks) {
    const header = headerFor(stack);
    let planText = "";
    try {
      const stackDir = path.join(process.env.GITHUB_WORKSPACE, stack);
      const planFile = path.join(stackDir, "out.tfplan");
      // Plan is written per-stack via: terramate run -- bash -c 'terragrunt plan -out "$(pwd)/out.tfplan" ...'
      // Terragrunt show needs the absolute plan path (relative paths resolve inside .terragrunt-cache).
      planText = execSync(`terragrunt show -no-color "${planFile}"`, {
        cwd: stackDir,
        encoding: "utf8",
        maxBuffer: 10 * 1024 * 1024,
      });
    } catch (error) {
      const detail = error.stdout?.toString() || error.stderr?.toString() || error.message;
      await upsertComment(
        header,
        [
          `## Plan — \`${stack}\``,
          "",
          ":boom: Failed to render plan output.",
          "",
          "```",
          detail.slice(0, 5000),
          "```",
        ].join("\n"),
      );
      continue;
    }

    if (planText.length > MAX_PLAN_CHARS) {
      planText =
        planText.slice(0, MAX_PLAN_CHARS) +
        "\n\n...(truncated — see the Actions log for the full plan)";
    }

    await upsertComment(
      header,
      [`## Plan — \`${stack}\``, "", "```terraform", planText, "```"].join("\n"),
    );
  }
};
