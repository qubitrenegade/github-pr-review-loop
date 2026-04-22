# Pre-Authorize Monitor + ScheduleWakeup via `allowed-tools` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the two edits from `docs/superpowers/specs/2026-04-22-allowed-tools-monitor-design.md` to `skills/github-pr-review-loop/SKILL.md` so `Monitor` and `ScheduleWakeup` are pre-authorized while the skill is active (no per-call allow-dialog) and "The loop" step 7 recommends `Monitor` as the primary polling mechanism.

**Architecture:** Minimal single-file change (two hunks landing in `skills/github-pr-review-loop/SKILL.md`): a 3-line `allowed-tools` block-sequence addition to the YAML frontmatter + a one-sentence rewrite of "The loop" step 7. No new files, no code, no tests.

**Tech Stack:** Plain Markdown + YAML frontmatter. Git. `gh` CLI.

**Branch:** `docs/implement-allowed-tools-monitor-9` (already created, based on `main` at `4f7a807`).

**Repo:** `qubitrenegade/github-pr-review-loop`.

**Spec reference (authoritative):** `docs/superpowers/specs/2026-04-22-allowed-tools-monitor-design.md`. Every edit below cites the spec.

---

## Task 1: SKILL.md — two coordinated edits

**Files:**
- Modify: `skills/github-pr-review-loop/SKILL.md`

**Spec sections:** SKILL.md changes #1 and #2.

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
head -5 skills/github-pr-review-loop/SKILL.md
grep -n "^allowed-tools:" skills/github-pr-review-loop/SKILL.md
grep -n "^7. Wait. Use \`ScheduleWakeup\` (Claude Code) or a cron / cadence" skills/github-pr-review-loop/SKILL.md
```

Expected:
- `head -5` shows the 4-line frontmatter block (`---`, `name:`, `description:`, `---`) plus the blank line after.
- `^allowed-tools:` grep: 0 matches (the key doesn't exist yet).
- Step-7 grep: one match with the current text `7. Wait. Use \`ScheduleWakeup\` (Claude Code) or a cron / cadence — never busy-poll. 4-5 min is a sensible interval.`.

If any mismatch, stop — re-read the spec and file before proceeding.

- [ ] **Step 2: Edit #1 — add `allowed-tools` block sequence to frontmatter**

Per spec SKILL.md change #1. The current frontmatter has two keys (`name`, `description`). Append a third key as a YAML block sequence. After the edit, the frontmatter should contain these four content lines between the `---` delimiters (plus the delimiters themselves):

```yaml
---
name: github-pr-review-loop
description: Drives GitHub PRs through Copilot review to merge via disciplined triage (apply / dismiss / clarify / defer / acknowledge), empirical dismissal of hallucinations, GraphQL-based re-request, and concrete stop conditions. Use for a Copilot-reviewed PR that needs driving to merge, for parallel batches of related PRs, or when deciding whether a Copilot finding is real.
allowed-tools:
  - Monitor
  - ScheduleWakeup
---
```

Use the Edit tool. The `old_string` should be the existing closing delimiter line as it appears in the file (`---` preceded by the `description:` line), and the `new_string` should be the three new lines (`allowed-tools:` + two list items) followed by the same `---`. Preserve the two-space indentation on the list items exactly — `allowed-tools:` at column 0, each `- Monitor` / `- ScheduleWakeup` prefixed by exactly two spaces before the hyphen.

- [ ] **Step 3: Edit #2 — rewrite "The loop" step 7**

Per spec SKILL.md change #2. The current step-7 line reads:

> 7. Wait. Use `ScheduleWakeup` (Claude Code) or a cron / cadence — never busy-poll. 4-5 min is a sensible interval.

Replace with:

> 7. Wait. Use `Monitor` (event-driven — emits as soon as Copilot posts a new review, ~30s reaction latency; preferred) or `ScheduleWakeup` (fixed cadence, 4-5 min intervals; fallback when `Monitor` isn't available or when you want cache-aware timing) — never busy-poll.

Use the Edit tool with the full old sentence as `old_string` and the full new sentence as `new_string`. Preserve the leading `7. ` step marker and any indentation.

- [ ] **Step 4: Verify edits landed**

Run:

```bash
head -8 skills/github-pr-review-loop/SKILL.md
grep -n "^allowed-tools:$" skills/github-pr-review-loop/SKILL.md
grep -n "^  - Monitor$" skills/github-pr-review-loop/SKILL.md
grep -n "^  - ScheduleWakeup$" skills/github-pr-review-loop/SKILL.md
grep -n "Monitor.*event-driven" skills/github-pr-review-loop/SKILL.md
grep -c "ScheduleWakeup (Claude Code) or a cron" skills/github-pr-review-loop/SKILL.md
```

Expected:
- `head -8` prints the updated frontmatter (8 lines: `---`, `name:`, `description:`, `allowed-tools:`, `  - Monitor`, `  - ScheduleWakeup`, `---`, blank).
- `^allowed-tools:$` grep → 1 match.
- `^  - Monitor$` grep → 1 match.
- `^  - ScheduleWakeup$` grep → 1 match.
- `Monitor.*event-driven` grep → 1 match (the new step 7).
- `ScheduleWakeup (Claude Code) or a cron` count → 0 (old step-7 wording fully replaced).

- [ ] **Step 5: Read-through check**

Open `skills/github-pr-review-loop/SKILL.md` and visually inspect:
- Frontmatter block renders as valid YAML (no extra blank lines inside the `---` block; `allowed-tools:` sits at column 0; list items are two-space-indented).
- "The loop" section still has 9 numbered steps; step 7 reads naturally with its new content; steps 6 and 8 are unchanged.
- No trailing whitespace introduced.

If anything is off, fix inline and re-run Step 4's greps.

- [ ] **Step 6: Commit**

```bash
git add skills/github-pr-review-loop/SKILL.md
git commit -m "docs(skill): pre-authorize Monitor + ScheduleWakeup via allowed-tools (#9)

Per docs/superpowers/specs/2026-04-22-allowed-tools-monitor-design.md:

- Add 'allowed-tools:' YAML block sequence to SKILL.md frontmatter
  with 'Monitor' and 'ScheduleWakeup' as pre-authorized tools. While
  this skill is active, invoking either no longer triggers the
  per-call permission allow-dialog.
- Rewrite 'The loop' step 7 to reference Monitor as the primary
  polling mechanism (event-driven, ~30s reaction latency) with
  ScheduleWakeup as fallback (fixed 4-5 min cadence).

Closes #9."
```

Note the `Closes #9` keyword — auto-closes the issue when the PR merges (per the lesson captured in our memory after missing it earlier in the batch).

---

## Task 2: Open PR + run Copilot review loop

**Scope:** Main session. Review loop needs conversational decision-making that doesn't delegate cleanly.

- [ ] **Step 1: Push branch**

```bash
git push -u origin docs/implement-allowed-tools-monitor-9
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "docs: pre-authorize Monitor + ScheduleWakeup via allowed-tools (#9)" --body "$(cat <<'EOF'
## Summary

Implementation PR for the spec merged at 4f7a807 (PR #19). Closes issue #9.

Two files ship: the skill file carrying the framing edit, plus the plan document as the audit trail.

Skill file edited:

- \`skills/github-pr-review-loop/SKILL.md\` — \`allowed-tools\` YAML block sequence added to frontmatter (pre-authorizes \`Monitor\` and \`ScheduleWakeup\` while this skill is active — no more per-call allow-dialogs); \`The loop\` step 7 rewritten to reference \`Monitor\` as the primary polling mechanism.

Plan doc:

- \`docs/superpowers/plans/2026-04-22-allowed-tools-monitor-implementation.md\` — the plan followed to make the skill edit.

## Net-new guidance

- **Monitor is the preferred polling primitive for Copilot review rounds** (event-driven, ~30s reaction latency) vs. \`ScheduleWakeup\` (fixed-interval fallback). Pre-authorizing both via the skill's \`allowed-tools\` means installing the skill on a fresh project no longer requires a manual \`.claude/settings.local.json\` allowlist entry before the first review-loop round.

## Out of scope

- Plugin-manifest-level permission declarations (not supported by Claude Code today).
- Broader event-driven tool set (\`RemoteTrigger\`, \`PushNotification\`, \`TaskStop\`) — additive follow-up if the skill grows to use them.

## Test plan

- [ ] Copilot review loop on this PR (dogfood).
- [ ] Standing merge authorization in effect: merge when Copilot converges cleanly AND no open questions.
- [ ] After merge: start a fresh Claude Code session invoking this skill in a repo where \`Monitor\` was previously prompting; confirm no allow-dialog fires.

Closes #9
Spec: \`docs/superpowers/specs/2026-04-22-allowed-tools-monitor-design.md\`
Plan: \`docs/superpowers/plans/2026-04-22-allowed-tools-monitor-implementation.md\`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Capture the PR number printed by `gh pr create`.

- [ ] **Step 3: Request Copilot review**

```bash
REPO="qubitrenegade/github-pr-review-loop"
PR_NUM="<the-number-gh-pr-create-just-printed>"
BOT_ID="BOT_kgDOCnlnWA"
PR_ID=$(gh pr view "$PR_NUM" --repo "$REPO" --json id --jq .id)
gh api graphql -f query='
  mutation($prId: ID!, $botId: ID!) {
    requestReviews(input: {pullRequestId: $prId, botIds: [$botId]}) {
      pullRequest { number }
    }
  }' -f prId="$PR_ID" -f botId="$BOT_ID"
```

- [ ] **Step 4: Run the review loop**

Handoff to the `github-pr-review-loop` skill's normal drill. Standing merge authorization is in effect for this PR per the user's 2026-04-22 grant: merge when Copilot comes back clean AND no open questions. Any question, dismissal needing judgment, or surprise → stop and flag the maintainer.

Stop condition + user merge authorization → squash-merge. The `Closes #9` keyword in the PR body will auto-close the issue.

---

## Self-review notes

- **Spec coverage:** Both spec edits map to Task 1 steps: Spec #1 (frontmatter) → Task 1 Step 2; Spec #2 (step 7) → Task 1 Step 3. Spec Verification section maps to Task 1 Step 4 (greps) + Step 5 (read-through).
- **Placeholder scan:** No TBDs. The `<the-number-gh-pr-create-just-printed>` in Task 2 Step 3 is a runtime substitution (implementer reads the number from Step 2's output). No literal placeholders requiring user action remain.
- **Type consistency:** Tool names `Monitor` and `ScheduleWakeup` match the spec exactly. Section heading `## The loop` and step number `7` match. Block-sequence formatting (two-space indent on list items) matches the spec's frontmatter example.
- **No new primitives:** Two-hunk single-file edit.
