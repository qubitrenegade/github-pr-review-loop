# Three Merge Gates + Verify-First Triage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the docs edits from spec `docs/superpowers/specs/2026-04-19-three-merge-gates-and-verify-first-design.md` to three skill files so the three merge gates (Copilot-review-loop-converged + CI-green + user-authorized) are each first-class in the reader's mental model, and so verification is step one on every triage disposition (not just Dismiss).

**Architecture:** Docs-only PR. No code changes. Three files get edits that re-parent existing guidance under clearer section headings, plus limited net-new content (conditional merge grant pattern, verify-first framing on Apply). Each file is edited independently in its own task; a final verification task cross-checks the three files for consistency.

**Tech Stack:** Plain Markdown. Git. `gh` CLI.

**Branch:** `docs/implement-three-merge-gates-verify-first` (already created, based on `main` at `b963be9`).

**Repo:** `qubitrenegade/github-pr-review-loop`.

**Spec reference (authoritative):** `docs/superpowers/specs/2026-04-19-three-merge-gates-and-verify-first-design.md`. Every edit below cites the spec section that defines it.

---

## Task 1: SKILL.md — five framing edits

**Files:**
- Modify: `skills/github-pr-review-loop/SKILL.md`

**Spec sections:** SKILL.md changes #1-#5

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "Every Copilot inline comment is one of four things" skills/github-pr-review-loop/SKILL.md
grep -n "Before merging: CI must be green" skills/github-pr-review-loop/SKILL.md
grep -n 'The user says "merge it"' skills/github-pr-review-loop/SKILL.md
```

Expected: first grep returns line ~27; second returns the heading line; third returns the bullet.

If any grep returns no match, stop — the spec's starting assumptions no longer hold against the current file. Re-read both the spec and the file before proceeding.

- [ ] **Step 2: Edit #1 — replace triage lead sentence**

Per spec SKILL.md change #1, replace:

> Every Copilot inline comment is one of four things. Decide explicitly; don't guess.

With:

> Every Copilot inline comment is a claim. Verify the claim first, then triage it into one of four dispositions: apply, dismiss, clarify, or defer. Verification is step one for *every* disposition, not just Dismiss.

Use the Edit tool with the exact strings above.

- [ ] **Step 3: Edit #2 — insert opener into "Before merging: CI must be green"**

Per spec SKILL.md change #2, insert this opener **as the first paragraph of the body** of the "Before merging: CI must be green" section (immediately after the heading, before the existing opening line that begins "**A stop condition firing is not permission to merge...**"):

```
> Merging requires three gates to clear: the Copilot review loop has converged (see Stop conditions — a stop condition has fired, whether that's zero new comments, repeats only, volume dried up, or user override), green CI (below), and user authorization (see Merge authorization). This section covers the CI gate; the other two have their own sections.
```

(The blockquote is part of the content — this opener is itself a blockquote paragraph.) Existing CI body stays as-is below the new opener.

- [ ] **Step 4: Edit #3 — insert new "Merge authorization" section**

Per spec SKILL.md change #3, add a new `## Merge authorization` section **between** the existing "Before merging: CI must be green" section and the existing "Stop conditions" section. Exact content:

```markdown
## Merge authorization

User authorization is one of three merge gates, peer to the Copilot review loop and CI gates. None of the three alone implies permission to merge.

Two modes grant the authorization:

- **Standing** — the maintainer is in the session and makes the merge call themselves. This covers both "user says merge" off-ramps mid-loop and the routine case of the maintainer reviewing a PR and hitting merge.
- **Conditional grant** — the maintainer grants permission up-front with scoped caveats, typically before stepping away. Example template:

  > "Merge when Copilot returns zero new comments AND CI is green. Wait for me if there are repeated comments, comments you have questions about, or red CI."

Any triggered caveat revokes the grant. If the grant says "wait on repeats," a repeat means wait, not "probably fine." Don't reinterpret caveats in light of how close the PR feels to merging.

Absent an explicit grant, the default is ping + wait. A converged review loop + green CI alone = permission to stop chasing review comments, not permission to merge.
```

- [ ] **Step 5: Edit #4 — insert Stop conditions preface**

Per spec SKILL.md change #4, insert this paragraph **as the new first line** under the `## Stop conditions` heading (before the existing "Stop when any of these fires..." line):

```
Every stop condition is "stop reviewing," not "ready to merge." Merging requires CI green (previous section) AND user authorization (see Merge authorization). A fired stop condition with red CI or no merge grant = permission to stop chasing review comments, nothing more.
```

- [ ] **Step 6: Edit #5 — remove "user says 'merge it'" bullet from Stop conditions list**

Per spec SKILL.md change #5, delete this bullet (and its accompanying continuation line if any) from the Stop conditions list:

```
- **The user says "merge it".** Explicit off-ramp, always valid.
```

Its content is now covered in the new "Merge authorization" section under **Standing** mode.

- [ ] **Step 7: Verify edits landed**

Run:

```bash
grep -n "Every Copilot inline comment is a claim" skills/github-pr-review-loop/SKILL.md
grep -n "Merging requires three gates to clear" skills/github-pr-review-loop/SKILL.md
grep -n "^## Merge authorization" skills/github-pr-review-loop/SKILL.md
grep -n "Every stop condition is" skills/github-pr-review-loop/SKILL.md
grep -nc 'The user says "merge it"' skills/github-pr-review-loop/SKILL.md
```

Expected: first four greps each return one line with the new content; the fifth (count) returns `0`.

- [ ] **Step 8: Commit**

```bash
git add skills/github-pr-review-loop/SKILL.md
git commit -m "docs(skill): three-gate merge framing + verify-first triage lead

Per docs/superpowers/specs/2026-04-19-three-merge-gates-and-verify-first-design.md (SKILL.md changes #1-#5):

- Reframe triage lead: verification is step one on every disposition
- Three-gate opener in 'Before merging: CI must be green'
- New 'Merge authorization' section covering standing + conditional-grant modes
- Stop conditions preface: 'stop != merge'
- Remove 'user says merge it' bullet from Stop conditions (now covered in Merge authorization / Standing mode)"
```

---

## Task 2: stop-conditions.md — four framing edits

**Files:**
- Modify: `skills/github-pr-review-loop/references/stop-conditions.md`

**Spec sections:** stop-conditions.md changes #1-#4

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "^## Merge precondition: required CI checks are green" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^## User escape hatch" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^## Putting it together" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^## Contents" skills/github-pr-review-loop/references/stop-conditions.md
```

Expected: all four return one line each with the heading line number.

- [ ] **Step 2: Edit #1 — insert new "Merge precondition: user authorization" section**

Per spec stop-conditions.md change #1, insert a new `## Merge precondition: user authorization` section **immediately after** the existing "Merge precondition: required CI checks are green" section ends, **before** the `## Primary stop: zero new findings` section begins. Exact content:

```markdown
## Merge precondition: user authorization

User authorization is one of three merge gates, peer to the CI and Copilot review loop gates. None of the three alone implies permission to merge.

Two modes grant the authorization:

- **Standing** — the maintainer is in the session and makes the merge call themselves (in-session "merge it", or the routine case of hitting the merge button after a review pass).
- **Conditional grant** — the maintainer grants permission up-front with scoped caveats, typically before stepping away. Template:

  > "Merge when Copilot returns zero new comments AND CI is green. Wait for me if there are repeated comments, comments you have questions about, or red CI."

Any triggered caveat revokes the grant and returns to the default ("wait for maintainer"). Don't reinterpret caveats in light of how close the PR feels to merging — the whole point of caveat language is to stop you when a particular signal fires, regardless of surrounding context.

Absent a grant, the default is ping + wait. A converged review loop + green CI alone is NOT permission to merge. Every merge needs all three gates: CI green (above), review loop converged (below), and user authorization (this section).
```

- [ ] **Step 3: Edit #2 — rename + refocus "User escape hatch" section**

Per spec stop-conditions.md change #2:

- Rename the heading `## User escape hatch` → `## User override of the review loop`.
- Replace the entire section body with:

```
If the maintainer says "stop" in-session, that overrides every other review-loop signal for continuing the review. Don't re-litigate. If the maintainer says "merge it," treat that under "Merge precondition: user authorization" above rather than in this override section — "merge it" is a merge-authorization signal, not a review-loop-stop signal.

This section exists because explicit maintainer "stop" (without an accompanying merge instruction) is a valid review-loop-stop signal: "I don't want you chasing this PR any further, regardless of whether it's merging now." Respect it.
```

- [ ] **Step 4: Edit #3 — rewrite "Putting it together" bullets**

Per spec stop-conditions.md change #3, find the bulleted list in `## Putting it together` whose bullets currently look like:

```
- Zero new comments on the latest pass → yes and yes → merge.
- New comments are repeats of addressed threads → yes and yes (action was the earlier fix) → merge.
- Volume trending to zero, and each remaining comment has been triaged under the usual apply/dismiss/clarify/defer → yes and yes → merge. Triage the nits the same way as any other finding; don't skip them because they're small.
- User says merge → yes → merge.
```

Replace the entire list with:

```
- Zero new comments on the latest pass → review signal exhausted. Merge if CI green AND user authorized (standing or conditional grant); otherwise stop chasing and ping maintainer.
- New comments are repeats of addressed threads → review signal exhausted (action was the earlier fix). Merge if CI green AND user authorized; otherwise stop chasing and ping maintainer.
- Volume trending to zero, and each remaining comment has been triaged under the usual apply/dismiss/clarify/defer → review signal exhausted. Merge if CI green AND user authorized; otherwise stop chasing and ping maintainer. Triage the nits the same way as any other finding; don't skip them because they're small.
- User says merge → merge authorization gate is satisfied (Standing mode). Verify CI green and that the review loop has at least one stop signal fired before merging — "merge authorization" alone doesn't skip the other two gates.
```

- [ ] **Step 5: Edit #4 — update Contents TOC**

Per spec stop-conditions.md change #4, update the `## Contents` bullet list. Current content:

```
- Merge precondition: required CI checks are green
- Primary stop: zero new findings on a Copilot pass
- Complement: zero unresolved conversation threads
- Secondary stop: Copilot repeats itself
- Tertiary stop: suggestion volume dries up
- User escape hatch
- Failure-mode stops
- Anti-patterns (don't stop for these reasons)
- Putting it together
```

Replace with:

```
- Merge precondition: required CI checks are green
- Merge precondition: user authorization
- Primary stop: zero new findings on a Copilot pass
- Complement: zero unresolved conversation threads
- Secondary stop: Copilot repeats itself
- Tertiary stop: suggestion volume dries up
- User override of the review loop
- Failure-mode stops
- Anti-patterns (don't stop for these reasons)
- Putting it together
```

- [ ] **Step 6: Verify edits landed**

Run:

```bash
grep -n "^## Merge precondition: user authorization" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^## User override of the review loop" skills/github-pr-review-loop/references/stop-conditions.md
grep -nc "^## User escape hatch" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "review signal exhausted" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "Merge authorization" skills/github-pr-review-loop/references/stop-conditions.md
```

Expected:
- First grep: one line (new section exists).
- Second grep: one line (renamed heading exists).
- Third grep (count): `0` (old heading is gone).
- Fourth grep: at least 3 lines (the rewritten Putting-it-together bullets).
- Fifth grep: at least 1 line (cross-reference to SKILL.md's Merge authorization section body, if present — at minimum the text "Merge precondition: user authorization" in Contents).

- [ ] **Step 7: Commit**

```bash
git add skills/github-pr-review-loop/references/stop-conditions.md
git commit -m "docs(stop-conditions): user-authorization gate + separate review-loop-stop from merge-auth

Per docs/superpowers/specs/2026-04-19-three-merge-gates-and-verify-first-design.md (stop-conditions.md changes #1-#4):

- New 'Merge precondition: user authorization' section (peer to the CI precondition)
- Rename 'User escape hatch' -> 'User override of the review loop', narrow scope to pure stop signals ('merge it' routes to the merge-auth section instead)
- Rewrite 'Putting it together' bullets to separate 'review signal exhausted' from 'merge'
- Update Contents TOC to match"
```

---

## Task 3: triage-patterns.md — four verify-first edits

**Files:**
- Modify: `skills/github-pr-review-loop/references/triage-patterns.md`

**Spec sections:** triage-patterns.md changes #1-#4

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "^## Contents" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Apply" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Evidence checklist" skills/github-pr-review-loop/references/triage-patterns.md
```

Expected: three lines, with the Contents heading near line 6, Apply around line 17, Evidence checklist much deeper (around line 195).

- [ ] **Step 2: Edit #1 — insert new "Verify first" section after Contents, before Apply**

Per spec triage-patterns.md change #1, insert a new `## Verify first` section between the end of the `## Contents` list and the start of the `## Apply` section. Exact content:

```markdown
## Verify first

Every Copilot finding is a *claim*. The discipline is the same regardless of disposition: verify the claim empirically, then pick based on what verification showed.

- Claim correct → **Apply** (the fix is real; include verification evidence in the reply when the claim was non-obvious).
- Claim wrong → **Dismiss** with that evidence.
- Can't tell → **Clarify**.
- Correct but out-of-scope → **Defer** with follow-up issue.

Applying without verifying is the more subtle trap than dismissing without verifying — Copilot confidently misremembers APIs, endpoints, and version strings, so a blindly-applied "just do what the reviewer said" can make the PR worse in a new way. See the Evidence Checklist (below) for commands to run per claim type.
```

- [ ] **Step 3: Edit #2 — move Evidence Checklist up**

Per spec triage-patterns.md change #2, cut the entire `## Evidence checklist` section (from its heading down to the end of the checklist table, stopping before the next `##` heading) from its current location (after Defer / Resolve) and paste it **immediately after** the new `## Verify first` section, before the `## Apply` section.

Result structure after this edit: Contents → Verify first → Evidence checklist → Apply → Dismiss → Clarify → Defer → Resolve → Batching → Special cases.

- [ ] **Step 4: Edit #3 — add verification-evidence guidance to Apply section**

Per spec triage-patterns.md change #3, find the existing Apply section body. After the paragraph that explains the "Fixed in `<sha>` — ..." template (the paragraph that ends with "Keep the one-sentence description specific enough to match the finding..."), append this new block:

```markdown
**For non-obvious claims, include the verification in the reply.** The reader benefits from knowing HOW you confirmed the finding was real — especially when Copilot re-surfaces the same claim in a later round. Obvious fixes (typos, broken links in files in the diff) don't need it; anything involving API paths, version pins, function signatures, or behavior claims does.

**Example (non-obvious claim):**

> Fixed in `abc1234` — verified via `grep 'ENTRY_POINT_GROUP' src/clickwork/discovery.py` that the group is `clickwork.commands` (no suffix). Updated 4 docs to match.

**Example (obvious claim — no verification needed):**

> Fixed in `def5678` — typo in README title.
```

- [ ] **Step 5: Edit #4 — update Contents TOC**

Per spec triage-patterns.md change #4, update the `## Contents` bullet list to reflect the new section order. Current content:

```
- Apply — fix + cite commit SHA
- Dismiss — reply with empirical evidence
- Clarify — ask before guessing
- Defer — out-of-scope but valid, file a follow-up issue
- Resolve the thread after replying
- Evidence checklist (what to run for each claim type)
- Batching multiple findings into one push
- Special cases
```

Replace with:

```
- Verify first — every finding is a claim, verify before triaging
- Evidence checklist (what to run for each claim type)
- Apply — fix + cite commit SHA (include verification for non-obvious claims)
- Dismiss — reply with empirical evidence
- Clarify — ask before guessing
- Defer — out-of-scope but valid, file a follow-up issue
- Resolve the thread after replying
- Batching multiple findings into one push
- Special cases
```

- [ ] **Step 6: Verify edits landed**

Run:

```bash
grep -n "^## Verify first" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Evidence checklist" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Apply" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "For non-obvious claims, include the verification in the reply" skills/github-pr-review-loop/references/triage-patterns.md
grep -c "^## Evidence checklist" skills/github-pr-review-loop/references/triage-patterns.md
```

Expected:
- First three greps: one line each, with `Verify first` line number < `Evidence checklist` line number < `Apply` line number.
- Fourth grep: one line (the new Apply-section block landed).
- Fifth grep (count): `1` — Evidence checklist appears exactly once (not duplicated if the move failed).

- [ ] **Step 7: Commit**

```bash
git add skills/github-pr-review-loop/references/triage-patterns.md
git commit -m "docs(triage): verify-first framing + move Evidence checklist up + Apply gets verification evidence

Per docs/superpowers/specs/2026-04-19-three-merge-gates-and-verify-first-design.md (triage-patterns.md changes #1-#4):

- New 'Verify first' section at top: every finding is a claim, verify before triaging
- Evidence checklist moved up (was buried after all four dispositions; now immediately after 'Verify first')
- Apply section: add 'For non-obvious claims, include the verification in the reply' guidance + two examples (API-grep verified, typo-no-verification)
- Update Contents TOC to match new order"
```

---

## Task 4: Cross-file verification sweep

**Files (read only):**
- `skills/github-pr-review-loop/SKILL.md`
- `skills/github-pr-review-loop/references/stop-conditions.md`
- `skills/github-pr-review-loop/references/triage-patterns.md`

**Spec section:** Verification.

- [ ] **Step 1: Consistency read-through**

Open all three files in the order SKILL.md → stop-conditions.md → triage-patterns.md and read them top to bottom.

Confirm each of these holds:

- The three-gate framing uses consistent wording everywhere: "Copilot review loop (converged / fired stop condition)" and "CI green" and "user authorization." No occurrences of "Copilot-clean" or "Copilot-review gate" (hyphenated) should remain in the net-new content.
- SKILL.md's Stop conditions list has three items, not four (the "user says merge" bullet is gone).
- stop-conditions.md's Contents lists the new "Merge precondition: user authorization" entry and shows "User override of the review loop" (not "User escape hatch").
- triage-patterns.md's section order is: Contents → Verify first → Evidence checklist → Apply → Dismiss → Clarify → Defer → Resolve → Batching → Special cases.

If any of these fail, stop and fix in the corresponding task's file before proceeding.

- [ ] **Step 2: Cross-reference link check**

Run:

```bash
# SKILL.md internally references "Merge authorization" — verify the section exists in SKILL.md itself
grep -c "^## Merge authorization" skills/github-pr-review-loop/SKILL.md

# stop-conditions.md references "Merge precondition: user authorization" from multiple places
grep -c "Merge precondition: user authorization" skills/github-pr-review-loop/references/stop-conditions.md

# triage-patterns.md's Verify first references Evidence Checklist
grep -c "Evidence Checklist" skills/github-pr-review-loop/references/triage-patterns.md
```

Expected: first grep returns `1`; second returns ≥2 (heading + at least one cross-reference); third returns ≥1 (the reference from Verify first).

If any count is lower than expected, a cross-reference is orphaned — find the referring text and either add the target heading or fix the reference text.

- [ ] **Step 3: Grep sweep for old conflation phrases**

Run:

```bash
# Literal "yes and yes -> merge" conflation pattern — must be gone
grep -rn "yes and yes" skills/github-pr-review-loop/ || echo "clean: no yes-and-yes->merge bullets remain"

# "user says merge" must appear in context of merge authorization / Standing, not in Stop conditions
grep -rn -A1 -B1 'user says "merge it"' skills/github-pr-review-loop/ || echo "clean: no stale stop-condition bullet"
grep -rn 'The user says "merge it"' skills/github-pr-review-loop/SKILL.md || echo "clean: SKILL.md has no merge-it bullet in Stop conditions"

# Hyphenated forms the spec's last review rounds eliminated
grep -rn "Copilot-review gate" skills/github-pr-review-loop/ || echo "clean: no Copilot-review hyphenation"
grep -rn "Copilot-clean" skills/github-pr-review-loop/ || echo "clean: no Copilot-clean shorthand"
```

Every grep should either return no matches (the "clean:" fallback echo prints) or return matches that are ACCEPTABLE (e.g., "user says merge" inside the Merge authorization section is fine; "user says merge" in the Stop conditions list is not).

Skim each match manually: every remaining occurrence of the searched phrase should be in a NEW or RE-PARENTED section, not in the OLD conflated context.

- [ ] **Step 4: Commit verification notes (if any issues found and fixed)**

If Steps 1-3 surfaced anything that needed fixing, the fix commit goes to whichever file was wrong (re-run the commit pattern from Tasks 1-3 for that file). If everything passed cleanly, no commit is needed for this task.

---

## Task 5: Open PR + run Copilot review loop

**Scope:** This task happens in the main session, NOT via subagent. The review loop needs conversational decision-making (triage calls, merge authorization from user) that doesn't delegate cleanly.

- [ ] **Step 1: Push branch**

```bash
git push -u origin docs/implement-three-merge-gates-verify-first
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "docs: three merge gates + verify-first triage (#5, #3)" --body "$(cat <<'EOF'
## Summary

Implementation PR for the spec merged at b963be9 (PR #8). Addresses issues #5 (merge-gate conflation) and #3 (verification-asymmetry on Apply).

Three skill files edited:

- `skills/github-pr-review-loop/SKILL.md` — triage lead, three-gate opener, new Merge authorization section, Stop conditions preface, remove "user says merge it" bullet
- `skills/github-pr-review-loop/references/stop-conditions.md` — new "Merge precondition: user authorization" section, rename + refocus "User escape hatch" -> "User override of the review loop", rewrite "Putting it together" bullets to separate "review signal exhausted" from "merge", update Contents
- `skills/github-pr-review-loop/references/triage-patterns.md` — new "Verify first" section, move Evidence Checklist up, add non-obvious-claim verification guidance to Apply, update Contents

Net-new guidance (not in the current docs):

- Conditional merge grant pattern (the "merge on clean + green; wait on repeats/questions" template the maintainer uses when stepping away)
- Verify-first on Apply (previously only implicit under Dismiss)

## Out of scope

Issues from the same batch that are explicitly NOT addressed in this PR: #2 (Acknowledge category), #4 (reply+resolve helper), #6 (outside-the-repo blockers), #7 (worktree cleanup). Each is a separate follow-up.

## Test plan

- [ ] Copilot review loop run on this PR (dogfood)
- [ ] Consistency read-through of the three files after any review-loop edits land
- [ ] Merge after Copilot signal exhausts + user authorization

Refs #5, #3
Spec: docs/superpowers/specs/2026-04-19-three-merge-gates-and-verify-first-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Request Copilot review**

```bash
REPO="qubitrenegade/github-pr-review-loop"
PR_NUM="<the-number-gh-pr-create-just-returned>"
BOT_ID="BOT_kgDOCnlnWA"
PR_ID=$(gh pr view "$PR_NUM" --repo "$REPO" --json id --jq .id)
gh api graphql -f query='
  mutation($prId: ID!, $botId: ID!) {
    requestReviews(input: {pullRequestId: $prId, botIds: [$botId]}) {
      pullRequest { number }
    }
  }' -f prId="$PR_ID" -f botId="$BOT_ID"
```

- [ ] **Step 4: Run the review loop (outside this plan)**

Handoff to the github-pr-review-loop skill's normal drill: wait for Copilot, triage each finding (apply / dismiss / clarify / defer — verify first!), reply + resolve per thread, re-request, repeat until a stop condition fires.

Stop condition + user merge authorization → merge. Same drill as the spec PR (#8) itself.

---

## Self-review notes

- **Spec coverage:** Every numbered edit in the spec (SKILL.md #1-#5, stop-conditions.md #1-#4, triage-patterns.md #1-#4) maps to a named step in Tasks 1-3. No spec requirement is orphaned.
- **Type consistency:** The section heading `## Merge authorization` in SKILL.md and `## Merge precondition: user authorization` in stop-conditions.md are intentionally different — one is in the top-level skill file (condensed), the other is in the reference doc (detailed). Cross-references use the appropriate form for each target.
- **Placeholder scan:** No TBDs, TODOs, or "implement later" items. Every edit step shows the exact before-text and after-text.
- **No new primitives introduced** — this is purely re-parenting + two net-new pieces of guidance already specified in the spec.
