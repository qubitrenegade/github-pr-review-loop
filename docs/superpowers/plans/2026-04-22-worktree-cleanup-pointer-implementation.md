# Worktree Cleanup Pointer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the single-bullet edit from `docs/superpowers/specs/2026-04-21-worktree-cleanup-pointer-design.md` so `SKILL.md`'s `## Scaling to multiple PRs` section points readers at the two superpowers skills that own worktree lifecycle (creation + cleanup).

**Architecture:** Single skill-file edit; docs-only PR with this plan as audit trail. One new bullet appended to the existing 3-bullet list in the Scaling section. No code changes, no other files.

**Tech Stack:** Plain Markdown. Git. `gh` CLI.

**Branch:** `docs/implement-worktree-cleanup-pointer-7` (already created, based on `main` at `3c4f39b`).

**Repo:** `qubitrenegade/github-pr-review-loop`.

**Spec reference (authoritative):** `docs/superpowers/specs/2026-04-21-worktree-cleanup-pointer-design.md`. The single SKILL.md edit is defined there.

---

## Task 1: SKILL.md — single-bullet append to the Scaling-to-multiple-PRs list

**Files:**
- Modify: `skills/github-pr-review-loop/SKILL.md`

**Spec sections:** SKILL.md changes #1

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "^## Scaling to multiple PRs" skills/github-pr-review-loop/SKILL.md
grep -n "^- One worktree per PR, branched from current main" skills/github-pr-review-loop/SKILL.md
grep -n "^- Scheduled wake-ups per PR" skills/github-pr-review-loop/SKILL.md
grep -n "^- Overlap the next wave's prep" skills/github-pr-review-loop/SKILL.md
grep -n "See \[references/wave-orchestration.md\]" skills/github-pr-review-loop/SKILL.md
grep -cn "Worktree lifecycle isn't owned by this skill" skills/github-pr-review-loop/SKILL.md
```

Expected:
- First five greps: one matching line each — the section heading, the three existing bullets in order, and the "See [references/wave-orchestration.md]..." paragraph that follows the bullet list.
- Last (count) grep: `0` — the new bullet hasn't been added yet.

If any mismatch, stop — the spec's starting assumptions no longer hold against the current file.

- [ ] **Step 2: Append the new bullet after the existing three**

Per spec SKILL.md change #1. Find the third bullet in the `## Scaling to multiple PRs` list (the one beginning `- Overlap the next wave's prep`). That bullet's text spans three lines in the file (wrapped at ~72 cols) and ends with the word `idle.` followed by a blank line.

After that third bullet (and before the "See [references/wave-orchestration.md]..." paragraph), insert a new 4th bullet. Exact content:

```markdown
- **Worktree lifecycle isn't owned by this skill.** If you have the
  `superpowers` plugin installed, see `superpowers:using-git-worktrees`
  for creation (directory selection, safety checks, setup) and
  `superpowers:finishing-a-development-branch` for cleanup after merge.
  Without that plugin, apply the same discipline manually:
  `git worktree add <path>` to create, `git worktree remove <path>`
  (plus removing the directory if files remain) after merge. Don't
  let stale worktrees accumulate — `gh pr merge --delete-branch`
  deletes the branches but leaves the worktree directory in place.
```

Use the Edit tool with the exact text above. Match indentation carefully — the continuation lines after the first are indented with TWO spaces (to align with the bullet's content, not the bullet marker).

The bullet uses hard-wrapped lines at ~72 cols matching the three preceding bullets' wrap style. Preserve the exact indentation and line breaks.

- [ ] **Step 3: Verify the edit landed**

Run:

```bash
grep -n "Worktree lifecycle isn't owned by this skill" skills/github-pr-review-loop/SKILL.md
grep -n "superpowers:using-git-worktrees" skills/github-pr-review-loop/SKILL.md
grep -n "superpowers:finishing-a-development-branch" skills/github-pr-review-loop/SKILL.md
grep -n "gh pr merge --delete-branch" skills/github-pr-review-loop/SKILL.md
grep -cn "Worktree lifecycle isn't owned by this skill" skills/github-pr-review-loop/SKILL.md
```

Expected:
- First grep: one match (the new bullet's opener).
- Second grep: one match (the new bullet's first skill reference).
- Third grep: at least one match (could be two: the bullet's reference by skill-id near the top, plus the same reference near the bottom of the bullet). Both are fine.
- Fourth grep: one match (the new bullet's reference to the merge flag).
- Last (count) grep: `1` exactly — the opener appears once, not duplicated.

- [ ] **Step 4: Read the Scaling section end-to-end**

Open `skills/github-pr-review-loop/SKILL.md` and skim the `## Scaling to multiple PRs` section (about 15-20 lines). Confirm:

- The 4 bullets all render as list items (new bullet hasn't accidentally broken into a paragraph).
- Indentation of the new bullet's continuation lines matches the preceding three bullets.
- The "See [references/wave-orchestration.md]..." paragraph immediately follows the last bullet with a blank line between them.
- No stray text landed above or below the new bullet.

If anything reads off, adjust the indentation or line-breaking inline and re-run Step 3.

- [ ] **Step 5: Commit**

```bash
git add skills/github-pr-review-loop/SKILL.md
git commit -m "docs(skill): worktree lifecycle pointer in Scaling section

Per docs/superpowers/specs/2026-04-21-worktree-cleanup-pointer-design.md:

- Append a 4th bullet to the ## Scaling to multiple PRs list pointing
  at superpowers:using-git-worktrees (creation) and
  superpowers:finishing-a-development-branch (cleanup) for readers
  who have the superpowers plugin installed, plus a manual fallback
  (git worktree add/remove) for readers who don't.

Worktree lifecycle isn't this skill's concern — the sibling skills
own creation and cleanup. This single pointer makes the hand-off
discoverable from the Scaling flow."
```

---

## Task 2: Verification + open PR + Copilot review loop

**Scope:** Main session, not subagent. Includes the tiny verification pass and the PR-open + review-loop drill.

- [ ] **Step 1: Read-through verification**

Open the edited SKILL.md and read the entire `## Scaling to multiple PRs` section. Confirm the 4-bullet list reads as parallel structure (no visual disruption from the new bullet's extra depth).

Confirm cross-references:

- `superpowers:using-git-worktrees` — referenced exactly as the full skill-ID form (no typos like `using-worktrees` or `git-worktrees`).
- `superpowers:finishing-a-development-branch` — same check (spec uses the full form).

Run:

```bash
grep -c "superpowers:using-git-worktrees" skills/github-pr-review-loop/SKILL.md
grep -c "superpowers:finishing-a-development-branch" skills/github-pr-review-loop/SKILL.md
```

Expected: both counts ≥1. Neither should be 0.

- [ ] **Step 2: Push branch**

```bash
git push -u origin docs/implement-worktree-cleanup-pointer-7
```

- [ ] **Step 3: Open PR**

```bash
gh pr create --title "docs: worktree lifecycle pointer in Scaling section (#7)" --body "$(cat <<'EOF'
## Summary

Implementation PR for the spec merged at d70da98 (PR #15). Addresses issue #7.

Two files ship: the skill file carrying the framing edit, plus the plan document as the audit trail.

Skill file edited:

- \`skills/github-pr-review-loop/SKILL.md\` — single new bullet appended to the \`## Scaling to multiple PRs\` list, pointing at \`superpowers:using-git-worktrees\` (creation) and \`superpowers:finishing-a-development-branch\` (cleanup) with a manual fallback (\`git worktree add/remove\`) for readers without the plugin.

Plan doc:

- \`docs/superpowers/plans/2026-04-22-worktree-cleanup-pointer-implementation.md\` — the plan followed to make the skill edit.

## Net-new guidance

- Worktree lifecycle isn't owned by this skill — the sibling superpowers skills own creation and cleanup. This pointer makes the hand-off discoverable from the Scaling flow so readers don't accumulate stale worktrees after \`gh pr merge --delete-branch\`.

## Out of scope

- **#4** (reply+resolve helper) — last remaining issue in the batch after this.

## Test plan

- [ ] Copilot review loop on this PR (dogfood)
- [ ] Standing merge authorization in effect: merge when Copilot converges cleanly AND no open questions
- [ ] After merge: close issue #7 with a PR-link comment

Refs #7
Spec: \`docs/superpowers/specs/2026-04-21-worktree-cleanup-pointer-design.md\`
Plan: \`docs/superpowers/plans/2026-04-22-worktree-cleanup-pointer-implementation.md\`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Capture the PR number printed by `gh pr create`.

- [ ] **Step 4: Request Copilot review**

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

- [ ] **Step 5: Run the review loop**

Standing merge authorization is in effect for this PR (per the user's 2026-04-22 grant): merge when Copilot comes back clean AND no open questions. Any question, dismissal that needs judgment, or surprise → stop and flag.

- [ ] **Step 6: Close issue #7 after merge**

After the implementation PR merges, close issue #7 with a comment referencing the merged PR:

```bash
gh issue close 7 --repo qubitrenegade/github-pr-review-loop \
  --comment "Closed by implementation PR #<N> (merged commit <sha>). Worktree lifecycle pointer lands in SKILL.md's Scaling-to-multiple-PRs section; creation/cleanup discipline itself lives in \`superpowers:using-git-worktrees\` and \`superpowers:finishing-a-development-branch\`."
```

Substitute `<N>` and `<sha>` with the actual implementation-PR number and the squash-merge SHA.

---

## Self-review notes

- **Spec coverage:** The spec has exactly one SKILL.md change (#1). Task 1 Step 2 implements it verbatim. Task 2 covers the spec's Verification section. Task 2 Step 6 closes the issue per the spec's "After this PR merges" note.
- **Placeholder scan:** The `<path>` in the bullet's `git worktree add <path>` / `git worktree remove <path>` is a shell-context placeholder (literal angle brackets, reader substitutes their own path) — part of the spec's verbatim text, not a plan failure. Task 2 Step 4's `<the-number-gh-pr-create-just-printed>` is a runtime substitution (implementer reads the PR number from Step 3's output). Task 2 Step 6's `<N>` and `<sha>` are the same pattern.
- **Type consistency:** Section heading `## Scaling to multiple PRs` and the bullet opener `**Worktree lifecycle isn't owned by this skill.**` appear consistently across Task 1 (verification greps) and Task 2 (read-through). Skill IDs `superpowers:using-git-worktrees` and `superpowers:finishing-a-development-branch` match the spec exactly.
- **No new primitives** — single-bullet edit.
