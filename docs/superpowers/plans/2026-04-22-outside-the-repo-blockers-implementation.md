# Outside-the-repo Blockers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the three docs edits from `docs/superpowers/specs/2026-04-20-outside-the-repo-blockers-design.md` to `stop-conditions.md` so the skill covers blockers outside the repo (account/org/DNS/vendor settings) with a 5-minute check, heuristics, and escalation template.

**Architecture:** Single-file docs PR. Three coordinated edits to `skills/github-pr-review-loop/references/stop-conditions.md`: a new peer section between Failure-mode stops and Anti-patterns, a cross-reference pointer appended to Failure-mode stops, and a matching Contents TOC entry. No code changes.

**Tech Stack:** Plain Markdown. Git. `gh` CLI.

**Branch:** `docs/implement-outside-the-repo-blockers-6` (already created, based on `main` at `d70da98`).

**Repo:** `qubitrenegade/github-pr-review-loop`.

**Spec reference (authoritative):** `docs/superpowers/specs/2026-04-20-outside-the-repo-blockers-design.md`. Every edit below cites the spec section that defines it.

---

## Task 1: stop-conditions.md — three coordinated edits

**Files:**
- Modify: `skills/github-pr-review-loop/references/stop-conditions.md`

**Spec sections:** stop-conditions.md changes #1, #2, #3

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "^## Failure-mode stops" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^## Anti-patterns — don't stop for these reasons" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^## Contents" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "A high-stakes \"must fix\" from Copilot" skills/github-pr-review-loop/references/stop-conditions.md
grep -cn "^- Outside-the-repo blockers" skills/github-pr-review-loop/references/stop-conditions.md
grep -cn "^## Outside-the-repo blockers" skills/github-pr-review-loop/references/stop-conditions.md
```

Expected:
- First four greps: one matching line each.
- Last two (count) greps: `0` each — the new content hasn't been added yet.

If any mismatch, stop and re-read the spec and file before proceeding.

- [ ] **Step 2: Edit #2 — append cross-reference pointer to Failure-mode stops**

Per spec stop-conditions.md change #2. Find the final paragraph of the existing `## Failure-mode stops` section (the paragraph that begins "**A high-stakes 'must fix' from Copilot that you can't verify.**" and ends with "Don't merge on hope."). Immediately after that paragraph, before the next section heading begins, append a blank line followed by:

```markdown
**External-system blockers have their own section below** — when the failure isn't about the review loop or this repo's code, see "Outside-the-repo blockers." Those blockers wear infra-bug costumes but can't be fixed from a PR.
```

This edit goes first because Edit #1 will insert a new section AFTER the Failure-mode-stops section; applying Edit #2 first keeps the sequencing clear.

- [ ] **Step 3: Edit #1 — insert new `## Outside-the-repo blockers` section**

Per spec stop-conditions.md change #1. Insert a new `## Outside-the-repo blockers` section between the end of the (now-extended) `## Failure-mode stops` section and the start of the existing `## Anti-patterns — don't stop for these reasons` section.

Structure after this edit: Failure-mode stops (with new pointer paragraph at the end) → Outside-the-repo blockers (new) → Anti-patterns.

Exact content for the new section:

```markdown
## Outside-the-repo blockers

Some failures look like infra-bug material — the deploy doesn't reach the public URL, a secret isn't reaching CI, an external service returns 4xx — but the root cause is a setting in a system this repo doesn't own. GitHub org / account configuration, DNS, PyPI project settings, upstream-vendor policies, custom-domain cascades. You can't fix these from a PR.

**The 5-minute check** — when the "this is an infra bug I need to investigate" muscle memory fires, run through this list before iterating:

1. Is the knob that would fix this inside this repo's clone? (Editable file, workflow, config.) If yes, fix it here. If no, keep going.
2. Is it a GitHub repo setting? (Settings tab on this repo: Pages, Actions secrets, branch protection, required checks.) If yes, needs repo-admin; flag to maintainer.
3. Is it a GitHub org or account setting? (Verified domains on user pages, org-level Actions policies, SSO rules, billing/quota.) If yes, needs org/account-owner; flag + move on.
4. Is it DNS, external service config, or vendor policy? (Registrar records, PyPI project settings, vendor support ticket.) If yes, not fixable from GitHub at all; flag + move on.

**Heuristics:**

- If you've spent more than ~5 minutes iterating on the same external surface without making the public behavior budge, stop iterating and apply the check above. The "try harder, the infra IS the bug" muscle memory is miscalibrated for outside-the-repo cases.
- Symptoms that usually indicate outside-the-repo: deploy pipelines succeed but public URL 404s; secret reaches Actions but external service rejects; workflow succeeds on fork but fails on upstream; CI workflow fails identically on `main` as on the PR.
- Symptoms that usually indicate in-repo-infra: failure references specific lines/files in this repo's workflow YAML; failure reproduces locally; failure is new since a recent commit.

**Escalation template:**

> Blocked: external. Verified in this PR: \<what succeeded (deploy ran, Pages API returned 201, etc.)>. Remaining symptom: \<what still fails (canonical URL 301→404)>. Suspected root cause: \<the specific account/org/DNS/vendor setting>. This is outside the repo's blast radius; filed as #\<N> for tracking, flagging to @\<maintainer> or @\<account-owner>. Moving on to next PR.

Three commitments: capture verified evidence, name the exact external knob, file a tracking issue. The tracking issue is what keeps it from dying silently.

**Concrete example** — on clickwork PR #99's docs-site deploy, the `mkdocs gh-deploy` step ran successfully and wrote to `gh-pages`; the Pages API enabled the site (returned 201). But `https://qubitrenegade.github.io/clickwork/` 301-redirected to `http://qubitrenegade.com/clickwork/`, which 404s. Root cause: the account owner had a verified custom domain (`qubitrenegade.com`) configured on their user-pages repo, which cascades to all project pages. Nothing in this repo could have fixed it. The fix was an account-level GitHub setting, not a code change. 15 minutes were spent iterating before the pattern surfaced; the 5-minute check would have caught it at step 3.
```

Keep the backslash escapes (`\<what succeeded...>`, `\<N>`, `@\<maintainer>`, `@\<account-owner>`) as literal text — those are Markdown escapes that make the angle brackets render as text, not HTML. Do not "fix" them to unescaped forms.

- [ ] **Step 4: Edit #3 — insert Contents TOC entry**

Per spec stop-conditions.md change #3. Update the `## Contents` bullet list at the top of stop-conditions.md. Insert a new entry between the existing `- Failure-mode stops` line and the existing `- Anti-patterns (don't stop for these reasons)` line:

```
- Outside-the-repo blockers
```

The resulting Contents list (for reference — verify against the actual file after your edit):

```
- Merge precondition: required CI checks are green
- Merge precondition: user authorization
- Primary stop: zero new findings on a Copilot pass
- Complement: zero unresolved conversation threads
- Secondary stop: Copilot repeats itself
- Tertiary stop: suggestion volume dries up
- User override of the review loop
- Failure-mode stops
- Outside-the-repo blockers
- Anti-patterns (don't stop for these reasons)
- Putting it together
```

- [ ] **Step 5: Verify edits landed**

Run:

```bash
grep -n "^## Outside-the-repo blockers" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^- Outside-the-repo blockers" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "\*\*External-system blockers have their own section below\*\*" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "5-minute check" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "Blocked: external" skills/github-pr-review-loop/references/stop-conditions.md
grep -cn "^## Outside-the-repo blockers" skills/github-pr-review-loop/references/stop-conditions.md
```

Expected:
- First five greps: one matching line each (the section heading, the TOC entry, the pointer paragraph, the 5-minute-check marker, the escalation-template opener).
- Last (count) grep: `1` exactly — the section heading appears once, not duplicated.

- [ ] **Step 6: Confirm section order**

Run:

```bash
grep -n "^## " skills/github-pr-review-loop/references/stop-conditions.md
```

Expected order (top to bottom):

```
## Contents
## Merge precondition: required CI checks are green
## Merge precondition: user authorization
## Primary stop: zero new findings
## Complement: zero unresolved conversation threads
## Secondary stop: Copilot repeats itself
## Tertiary stop: volume drying up
## User override of the review loop
## Failure-mode stops
## Outside-the-repo blockers
## Anti-patterns — don't stop for these reasons
## Putting it together
```

The new `## Outside-the-repo blockers` heading must appear between `## Failure-mode stops` and `## Anti-patterns — don't stop for these reasons`. If it lands anywhere else, the insertion point was wrong — revert and redo Edit #1.

- [ ] **Step 7: Commit**

```bash
git add skills/github-pr-review-loop/references/stop-conditions.md
git commit -m "docs(stop-conditions): add Outside-the-repo blockers section

Per docs/superpowers/specs/2026-04-20-outside-the-repo-blockers-design.md (stop-conditions.md changes #1, #2, #3):

- New peer section '## Outside-the-repo blockers' between Failure-mode stops and Anti-patterns, with a 5-minute check, heuristics, escalation template, and the clickwork PR #99 Pages/custom-domain example as the anchor case
- Pointer paragraph appended to Failure-mode stops so readers scanning that section find the new one
- Contents TOC entry matching the new heading"
```

---

## Task 2: Cross-file verification sweep

**Files (read only):**
- `skills/github-pr-review-loop/references/stop-conditions.md`
- `skills/github-pr-review-loop/SKILL.md`
- `skills/github-pr-review-loop/references/triage-patterns.md`
- `skills/github-pr-review-loop/references/wave-orchestration.md`

**Spec section:** Verification.

This task is main-session, not subagent — it's a skim-based judgment check rather than mechanical edits.

- [ ] **Step 1: Read-through the edited section**

Open `skills/github-pr-review-loop/references/stop-conditions.md` and read the new `## Outside-the-repo blockers` section top to bottom, plus the preceding `## Failure-mode stops` (with its new pointer paragraph) and the following `## Anti-patterns` section.

Confirm:

- The pointer paragraph at the end of Failure-mode stops reads naturally and sets up the next section.
- The new section's 5-minute-check numbered list is ordered from most-likely-fixable-here (step 1) to least (step 4).
- The heuristics bullets distinguish outside-the-repo symptoms from in-repo-infra symptoms clearly.
- The escalation template's three commitments (verified evidence, named knob, tracking issue) are all present.
- The concrete example at the bottom is specific and matches the spec's Problem-section description.

If the prose feels off (broken transition, orphaned phrasing, inconsistency with surrounding sections), fix it.

- [ ] **Step 2: Cross-reference / anchor check**

The new section's only cross-references are:

- The pointer from `## Failure-mode stops` to "Outside-the-repo blockers" (by section-name, not markdown anchor — this is prose).
- The new TOC entry "Outside-the-repo blockers" should exactly match the `## Outside-the-repo blockers` heading.

Run:

```bash
# Both should match exactly (string comparison)
grep -n "^- Outside-the-repo blockers$" skills/github-pr-review-loop/references/stop-conditions.md
grep -n '^## Outside-the-repo blockers$' skills/github-pr-review-loop/references/stop-conditions.md
```

Both greps should return one line each. If either is missing, the pointer/heading match is broken.

- [ ] **Step 3: Grep sweep for keywords**

Per the spec Verification section #3, the keywords `5-minute check` and `Outside-the-repo blockers` should appear in the new section and TOC and nowhere else in the skill (apart from the already-merged spec and plan files under `docs/`). Run:

```bash
grep -rn "5-minute check" skills/github-pr-review-loop/
grep -rn "Outside-the-repo blockers" skills/github-pr-review-loop/
```

Expected: both only match within `stop-conditions.md` (multiple hits in that file are fine — section heading, TOC entry, and any internal references).

- [ ] **Step 4: Commit verification fixes (if any)**

If Steps 1-3 surfaced anything that needed fixing, fix in a new commit (reuse the Task 1 commit message pattern). If everything passed cleanly, no commit is needed for this task.

---

## Task 3: Open PR + run Copilot review loop

**Scope:** Main session, not subagent. The review loop needs conversational decision-making that doesn't delegate cleanly.

- [ ] **Step 1: Push branch**

```bash
git push -u origin docs/implement-outside-the-repo-blockers-6
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "docs: add Outside-the-repo blockers section (#6)" --body "$(cat <<'EOF'
## Summary

Implementation PR for the spec merged at e18b880 (PR #13). Addresses issue #6.

Two files ship: the **skill file** carrying the framing edit, plus the **plan document** as the audit trail.

Skill file edited:

- \`skills/github-pr-review-loop/references/stop-conditions.md\` — new peer section \`## Outside-the-repo blockers\` with the 5-minute check, heuristics, escalation template, and clickwork PR #99 Pages/custom-domain anchor example; pointer paragraph appended to Failure-mode stops; Contents TOC entry.

Plan doc:

- \`docs/superpowers/plans/2026-04-22-outside-the-repo-blockers-implementation.md\` — the plan followed to make the skill edits.

## Net-new guidance

- **Outside-the-repo blockers** — blockers that look like infra bugs but are rooted in account/org/DNS/vendor settings. A PR can't fix them; iterate on the repo won't help. Now has a dedicated section with a 5-minute triage check and an escalation template.

## Out of scope

Each gets its own follow-up PR: #4 (reply+resolve helper), #7 (worktree cleanup — spec merged at d70da98, impl next).

## Test plan

- [ ] Copilot review loop on this PR (dogfood)
- [ ] Standing merge authorization: merge when Copilot returns clean AND no open questions (per the new Merge-authorization contract in SKILL.md)

Refs #6
Spec: \`docs/superpowers/specs/2026-04-20-outside-the-repo-blockers-design.md\`
Plan: \`docs/superpowers/plans/2026-04-22-outside-the-repo-blockers-implementation.md\`

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

Handoff to the github-pr-review-loop skill's normal drill. Standing merge authorization is in effect for this PR (per the user's 2026-04-22 grant): merge when Copilot comes back clean AND no open questions. Any question or surprise → stop and flag the maintainer.

---

## Self-review notes

- **Spec coverage:** All three numbered spec edits (stop-conditions.md changes #1, #2, #3) map to named steps in Task 1 (Step 3 = Edit #1, Step 2 = Edit #2, Step 4 = Edit #3). Verification section of the spec maps to Task 2.
- **Placeholder scan:** No TBDs or TODOs. Template placeholders (`\<N>`, `\<what succeeded...>`, `@\<maintainer>`, `@\<account-owner>`) are intentional Markdown escapes that render as literal angle brackets in the rendered doc; the plan calls out that they must be preserved.
- **Type consistency:** Section heading `## Outside-the-repo blockers` and TOC entry `- Outside-the-repo blockers` use the same string. The pointer paragraph in Failure-mode stops uses the same title in quotes. All three match.
- **No new primitives** — single-file docs edit; no new files created except this plan doc itself.
