# Outside-the-repo blockers — design

**Date:** 2026-04-20
**Issue:** [#6](https://github.com/qubitrenegade/github-pr-review-loop/issues/6)
**Type:** Docs / framing PR — no code changes.

## Problem

The `github-pr-review-loop` skill's current blocker-handling coverage is review-loop-focused:

- `triage-patterns.md` — Defer with follow-up issue for "valid but out of scope."
- `wave-orchestration.md` → "Cross-PR failure modes" — for fixes that span multiple PRs in the same wave.
- `stop-conditions.md` → "Failure-mode stops" — in-loop failures (Copilot hallucinating, CI red on main, thread devolved, etc.).

What the skill doesn't cover: blockers **outside the repo entirely** — account-level config, GitHub org settings, DNS, PyPI project settings, external services, upstream-vendor policies. These look like infra-bug material but are in a different blast radius. You can't fix them from a PR.

**Concrete case:** on the clickwork docs-site cycle, merging PR #99 triggered the `mkdocs gh-deploy` step, which wrote to `gh-pages` successfully; GitHub Pages was enabled via `gh api` and returned 201; the site's `gh-pages` branch had `index.html`, `assets/`, `explanation/`, `reference/` all present. But the canonical URL `https://qubitrenegade.github.io/clickwork/` 301-redirected to `http://qubitrenegade.com/clickwork/`, which 404s.

Root cause: the account owner had a verified custom domain (`qubitrenegade.com`) configured on their user-pages repo. GitHub's user-level-custom-domain setup cascades to all project pages, so *every* `qubitrenegade.github.io/*` project redirects. Not a per-repo setting; nothing in this repo could fix it.

Observed behavior without this framing: ~15 minutes were spent iterating on DNS, Pages config, `mkdocs.yml` `site_url`, and probing the redirect. The "try harder, the infra IS the bug" muscle memory kept the loop going. A 5-minute check for "is the knob inside this repo's clone?" would have caught it at step 3 ("Is it a GitHub org or account setting?").

## Design

### Scope

This document describes a separate follow-up implementation PR (this PR, which lands the spec, is not that one).

The implementation PR will be a single-file docs PR touching `skills/github-pr-review-loop/references/stop-conditions.md`:

- New peer section `## Outside-the-repo blockers`, inserted between the existing `## Failure-mode stops` and `## Anti-patterns — don't stop for these reasons`.
- One-line pointer appended to the end of the existing `## Failure-mode stops` section so a reader scanning that section finds the new one.
- Contents TOC updated with the new section entry.

No code changes in the implementation PR. No other files touched in the implementation PR. (This spec PR, on the other hand, adds only the spec file.)

**Out of scope** (each gets its own later PR): #4 (reply+resolve helper), #7 (worktree cleanup).

### Design choices (locked in during brainstorm)

- **Peer section, not subsection.** A subsection under `Failure-mode stops` was considered but rejected — outside-the-repo blockers have a different blast radius (account/org/DNS/vendor) from review-loop failures (Copilot hallucinating, CI red unrelated). Burying as a subsection understates the category; a peer section lets it have its own full treatment.
- **Checklist + escalation template + heuristics.** This combination gives the reader a complete recipe: (a) the 5-minute check as a numbered list, (b) concrete heuristics for recognizing the pattern, (c) a template for the "flag + file + move on" step. Mirrors how Apply/Dismiss/Defer each have templates elsewhere in the skill. A minimal-heuristics-only version is too loose; a checklist-only version stops short of the actionable primitive.
- **Single file.** A separate new file plus `SKILL.md` pointer was considered but rejected as over-engineered for the content volume; the single `stop-conditions.md` section is the right place.

### stop-conditions.md changes

#### 1. New `## Outside-the-repo blockers` section

Insert immediately after the existing `## Failure-mode stops` section ends (after the "A high-stakes 'must fix' from Copilot that you can't verify..." paragraph), and immediately before `## Anti-patterns — don't stop for these reasons` begins. Exact content:

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

#### 2. Append cross-reference pointer to `## Failure-mode stops`

The existing `## Failure-mode stops` section ends with the "A high-stakes 'must fix' from Copilot that you can't verify..." paragraph. Append a new short paragraph at the end of the section (before the new `## Outside-the-repo blockers` heading):

```markdown
**External-system blockers have their own section below** — when the failure isn't about the review loop or this repo's code, see "Outside-the-repo blockers." Those blockers wear infra-bug costumes but can't be fixed from a PR.
```

#### 3. Update Contents TOC

Update the `## Contents` bullet list at the top of stop-conditions.md. Insert between the `Failure-mode stops` entry and the `Anti-patterns (don't stop for these reasons)` entry:

```
- Outside-the-repo blockers
```

The resulting TOC (after this PR's edit):

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

## Verification

Docs-only PR; "testing" means:

1. **Read-through check** — read stop-conditions.md top-to-bottom after edits. Confirm the new section reads cleanly between Failure-mode stops and Anti-patterns. Confirm the Failure-mode-stops pointer clearly directs readers to Outside-the-repo blockers.
2. **Pointer / heading check** — confirm the reference from `## Failure-mode stops` to Outside-the-repo blockers is present and unambiguous. The pointer is prose (`see "Outside-the-repo blockers"`), not a markdown link, so matching-section-name is what makes it resolve; the new section's Contents TOC entry should match the heading text exactly.
3. **Grep sweep** — search for the `5-minute check` keywords (should appear in the new section and nowhere else) and for `Outside-the-repo blockers` heading (should appear in both TOC and section).
4. **Copilot review loop** — run the normal drill per the skill itself.

No automated tests. No code changes.

## Out-of-scope / follow-ups

- **#4** (reply+resolve helper script)
- **#7** (worktree cleanup)

Each will get its own follow-up PR.
