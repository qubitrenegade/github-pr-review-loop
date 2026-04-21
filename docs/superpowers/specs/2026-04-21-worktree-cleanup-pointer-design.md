# Worktree cleanup pointer — design

**Date:** 2026-04-21
**Issue:** [#7](https://github.com/qubitrenegade/github-pr-review-loop/issues/7)
**Type:** Docs / framing PR — no code changes.

## Problem

The `github-pr-review-loop` skill mentions using worktrees in its `## Scaling to multiple PRs` section ("One worktree per PR, branched from current main.") and in `wave-orchestration.md`, but gives no guidance on their lifecycle. In practice, worktrees accumulate after `gh pr merge --delete-branch` — the remote branch gets deleted, `gh` may drop the local branch too, but the worktree directory stays until someone runs `git worktree remove <path>` and cleans up the directory.

Issue #7 asked "should we consider cleaning up worktrees after we merge a branch?"

The answer, after brainstorming: **this skill shouldn't own worktree lifecycle.** That's `superpowers:using-git-worktrees` (creation) and `superpowers:finishing-a-development-branch` (cleanup). Both skills already exist and prescribe the discipline. What this skill is missing is a **discoverability pointer** — a reader following the `github-pr-review-loop` flow into the Scaling section encounters "use worktrees" but no onward link to the lifecycle skills.

## Design

### Scope

Single-file, single-bullet edit to `skills/github-pr-review-loop/SKILL.md`. No new content, no new patterns — just a pointer to the existing sibling skills so the hand-off is discoverable.

After merging the implementation PR, comment on issue #7 linking to the merged PR and close the issue.

**Out of scope** — no script, no hook, no new lifecycle content. The discipline itself lives in the other skills; this PR only surfaces the pointer.

### Design choices (locked in during brainstorm)

- **Docs pointer, not prescriptive lifecycle content.** Option A (document the cleanup steps here), Option B (ship a helper script), Option C (git post-merge hook) were all considered but rejected. Worktree cleanup is not this skill's concern — `superpowers:finishing-a-development-branch` already owns that discipline. Duplicating it here would create drift between the two skills. The right move is a short cross-reference.
- **Close the issue with the PR link** — makes the trail findable. "Not our problem, see these other skills" is a complete answer when it comes with a pointer.

### SKILL.md changes

#### 1. Add a worktree-lifecycle pointer bullet to the Scaling section's bullet list

The existing `## Scaling to multiple PRs` section has a 3-bullet list describing orchestration around parallel PRs. Current bullets (for reference — do not modify the existing three):

- One worktree per PR, branched from current main. Isolates concurrent edits...
- Scheduled wake-ups per PR at staggered intervals...
- Overlap the next wave's prep (branch creation, agent briefing)...

Append a new 4th bullet after the existing three, before the "See [references/wave-orchestration.md]..." paragraph that follows the list:

```markdown
- **Worktree lifecycle isn't owned by this skill.** See `superpowers:using-git-worktrees` for creation (directory selection, safety checks, setup) and `superpowers:finishing-a-development-branch` for cleanup after merge. Don't let stale worktrees accumulate — `gh pr merge --delete-branch` removes the remote branch but leaves the local worktree directory in place until the finishing-a-development-branch discipline runs.
```

## Verification

Docs-only; single-bullet edit:

1. **Read-through check** — open SKILL.md's Scaling section and confirm the 4 bullets read cleanly together. The new bullet shouldn't break parallel structure with the existing three.
2. **Cross-reference check** — confirm both `superpowers:using-git-worktrees` and `superpowers:finishing-a-development-branch` are referenced by their correct skill-ID form.
3. **Copilot review loop** — run the normal drill.

After merge: post a comment on issue #7 linking to the merged PR, then close the issue.

No automated tests. No code changes.

## Out-of-scope / follow-ups

- **#4** (reply+resolve helper script) — distinct effort, own PR.

After this PR merges, #4 is the last remaining issue in the batch that motivated the #5+#3, #2, and #6 spec cycles.
