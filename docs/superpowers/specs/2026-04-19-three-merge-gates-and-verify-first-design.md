# Three merge gates + verify-first triage — design

**Date:** 2026-04-19
**Issues:** [#5](https://github.com/qubitrenegade/github-pr-review-loop/issues/5), [#3](https://github.com/qubitrenegade/github-pr-review-loop/issues/3)
**Type:** Docs / framing PR — no code changes.

## Problem

Two related framing gaps in the `github-pr-review-loop` skill, both caught during real use on the clickwork 1.0 docs-site cycle:

1. **Merge-gate conflation (#5).** The skill's "stop conditions" list can read as "stop = merge." In practice this almost caused a merge on red CI twice. The current doc already names CI-green as a separate gate, but the three gates that must all clear (Copilot-clean, CI-green, user-authorized) aren't structurally first-class. User-authorization specifically isn't called out as its own gate — the `User escape hatch` section conflates "user says stop" with "user says merge" and doesn't document the common real pattern of a *conditional merge grant* (e.g., "merge on clean + green; wait on repeats/questions before stepping away").

2. **Verification-asymmetry (#3).** The skill puts the verification burden on Dismiss (lead with evidence) and treats Apply as near-reflex (fix, commit, cite SHA). But Copilot confidently misremembers APIs, endpoints, and version strings — applying a plausible-sounding suggestion verbatim can break the PR in a new way. The more subtle trap is a suggestion that looks safe to apply but is also wrong.

## Design

### Scope

This spec describes a follow-up **implementation PR** (separate from the PR that lands this spec doc). The implementation PR will be a bundled docs PR touching three files:

- `skills/github-pr-review-loop/SKILL.md`
- `skills/github-pr-review-loop/references/stop-conditions.md`
- `skills/github-pr-review-loop/references/triage-patterns.md`

No code changes. No new primitives. Existing guidance is preserved and re-parented under clearer section headings.

**Out of scope** (each gets its own later PR): #2 (Acknowledge triage category), #4 (reply+resolve helper), #6 (outside-the-repo blockers), #7 (worktree cleanup).

### SKILL.md changes

#### 1. Triage lead sentence (under the "The triage — apply, dismiss, clarify, or defer" heading)

Replace the opener sentence:

> Every Copilot inline comment is one of four things. Decide explicitly; don't guess.

With:

> Every Copilot inline comment is a claim. Verify the claim first, then triage it into one of four dispositions: apply, dismiss, clarify, or defer. Verification is step one for *every* disposition, not just Dismiss.

#### 2. "Before merging: CI must be green" opener (inserted before existing body)

Add a brief opener re-framing the section as one of three gates:

> Merging requires three gates to clear: the Copilot review loop has converged (see Stop conditions — a stop condition has fired, whether that's zero new comments, repeats only, volume dried up, or user override), green CI (below), and user authorization (see Merge authorization). This section covers the CI gate; the other two have their own sections.

Existing CI body stays as-is.

#### 3. New "Merge authorization" section (between "Before merging: CI must be green" and "Stop conditions")

~150 words covering:

- User authorization is one of three merge gates, peer to the Copilot-review and CI gates. None of the three alone implies permission to merge.
- Two modes:
  - **Standing** — the maintainer is in the session and makes the merge call themselves.
  - **Conditional grant** — the maintainer grants permission up-front with scoped caveats, typically before stepping away. Example template:
    > "Merge when Copilot returns zero new comments AND CI is green. Wait for me if there are repeated comments, comments you have questions about, or red CI."
- Any triggered caveat revokes the grant. If the grant says "wait on repeats," a repeat means wait, not "probably fine."
- Absent an explicit grant, the default is ping + wait. A converged review loop + green CI alone = permission to stop chasing, not permission to merge.

#### 4. Stop conditions preface (inserted immediately under the "Stop conditions" heading)

Add as the new first line of the section:

> Every stop condition is "stop reviewing," not "ready to merge." Merging requires CI green (previous section) AND user authorization (see Merge authorization). A fired stop condition with red CI or no merge grant = permission to stop chasing review comments, nothing more.

#### 5. Remove the "user says 'merge it'" bullet from the Stop conditions list

The current Stop conditions list ends with:

> - **The user says "merge it".** Explicit off-ramp, always valid.

Remove this bullet. It conflates a merge-authorization signal with a stop-reviewing signal — exactly the conflation this spec is designed to eliminate. The content is covered in the new "Merge authorization" section under the **Standing** mode (maintainer in-session making the merge call). Leaving it in Stop conditions would contradict the new preface added in edit 4 above.

### stop-conditions.md changes

#### 1. New peer section "Merge precondition: user authorization"

Insert immediately after the existing "Merge precondition: required CI checks are green" section, before the "Primary stop: zero new findings" section.

~180 words covering:

- User authorization is one of three merge gates, peer to the CI and Copilot-review gates. None of the three alone implies permission to merge.
- Two modes: standing (maintainer in-session) or conditional grant (scoped up-front permission).
- Conditional-grant template (same as SKILL.md):
  > "Merge when Copilot returns zero new comments AND CI is green. Wait for me if there are repeated comments, comments you have questions about, or red CI."
- Any triggered caveat revokes the grant and returns to default ("wait for maintainer"). Don't reinterpret caveats.
- Absent a grant, the default is ping + wait. A converged review loop + green CI alone is NOT permission to merge.

#### 2. Refocus "User escape hatch" section

Rename the existing "User escape hatch" heading → "User override of the review loop."

Narrow scope to *stopping the review*, not authorizing the merge:

> If the maintainer says "stop" in-session, that overrides every other review-loop signal for continuing the review. Don't re-litigate. If the maintainer says "merge it," treat that under "Merge precondition: user authorization" above rather than in this override section.

Body shrinks to match — this section is only about stopping the review; the "merge it" case has its own dedicated section above.

#### 3. Update "Putting it together" section

Current pattern (in the bulleted list of "has the reviewer told me what it has to tell me, and have I acted on it?" cases):

> - Zero new comments on the latest pass → yes and yes → merge.

Replace each bullet to separate "review signal exhausted" from "merge":

> - Zero new comments on the latest pass → review signal exhausted. Merge if CI green AND user authorized (standing or conditional grant); otherwise stop chasing and ping maintainer.

Same pattern applied to all four bullets in that list. Note: the fourth bullet ("User says merge") moves out of the stop-conditions framing — its content belongs in the Merge authorization context per the new structure. Update it to make that clear (e.g., "User says merge → merge authorization gate is satisfied; check CI green and the review loop has at least one stop signal fired before merging").

#### 4. Update Contents

Update the `## Contents` bullet list at the top of stop-conditions.md to reflect the new and renamed sections:

- Add a new entry for "Merge precondition: user authorization" between the existing CI-precondition entry and "Primary stop: zero new findings on a Copilot pass".
- Rename the existing "User escape hatch" entry → "User override of the review loop".
- Remove any stale entries if the refactor above eliminates them.

### triage-patterns.md changes

#### 1. New "Verify first" section at top (after Contents, before Apply)

~120 words:

> Every Copilot finding is a *claim*. The discipline is the same regardless of disposition: verify the claim empirically, then pick based on what verification showed.
>
> - Claim correct → **Apply** (the fix is real; include verification evidence in the reply when the claim was non-obvious).
> - Claim wrong → **Dismiss** with that evidence.
> - Can't tell → **Clarify**.
> - Correct but out-of-scope → **Defer** with follow-up issue.
>
> Applying without verifying is the more subtle trap than dismissing without verifying — Copilot confidently misremembers APIs, endpoints, and version strings, so a blindly-applied "just do what the reviewer said" can make the PR worse. See Evidence Checklist (below) for commands to run per claim type.

#### 2. Move Evidence Checklist up

The Evidence Checklist section is currently buried after all four disposition sections (Apply, Dismiss, Clarify, Defer). Move it to immediately follow "Verify first" so it's reachable before any disposition template.

#### 3. Update Apply section

Add after the existing template explanation (in the "Apply" section):

> **For non-obvious claims, include the verification in the reply.** The reader benefits from knowing HOW you confirmed the finding was real — especially when Copilot re-surfaces the same claim in a later round. Obvious fixes (typos, broken links in files in the diff) don't need it; anything involving API paths, version pins, function signatures, or behavior claims does.
>
> **Example (non-obvious claim):**
>
> > Fixed in `abc1234` — verified via `grep 'ENTRY_POINT_GROUP' src/clickwork/discovery.py` that the group is `clickwork.commands` (no suffix). Updated 4 docs to match.
>
> **Example (obvious claim — no verification needed):**
>
> > Fixed in `def5678` — typo in README title.

#### 4. Update Contents

Update the "## Contents" bullet list at the top of triage-patterns.md to reflect the new order: Verify first → Evidence Checklist → Apply → Dismiss → Clarify → Defer → Resolve → Batching → Special cases.

## Verification

Docs-only PR; "testing" means:

1. **Read-through check** — after edits, re-read each file top-to-bottom to confirm the three-gate framing is consistent across all three files. No section contradicts another.
2. **Link check** — cross-references between sections resolve to the right place. Notably: SKILL.md's "see Merge authorization" points at SKILL.md's *own* new Merge authorization section (same file), and any cross-links between SKILL.md and stop-conditions.md's user-authorization treatments (both files now cover the gate) point at each other's intended sections.
3. **Grep sweep** — search for old *conflation* phrases specifically (e.g., `yes and yes → merge`, direct `stop → merge` equations, `permission to merge` used where the correct meaning is "permission to stop chasing") across the three files. `stop condition` itself is a valid term that stays, so don't grep for it — it will always hit and isn't useful signal.
4. **Copilot review loop** — run the normal drill per the skill itself. Dogfood it on the PR.

No automated tests. No code changes.

## Out-of-scope / follow-ups

Issues from the same batch that are explicitly NOT addressed in the implementation PR this spec describes:

- **#2** (Acknowledge triage category for design-voting): separate docs PR later.
- **#4** (reply+resolve helper script): biggest effort; separate plan + implementation cycle.
- **#6** (outside-the-repo blockers escalation guidance): separate docs PR later.
- **#7** (worktree cleanup): needs a brainstorm on scope before any implementation.
