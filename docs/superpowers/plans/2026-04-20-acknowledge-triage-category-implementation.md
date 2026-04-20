# Acknowledge Triage Category Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the docs edits from spec `docs/superpowers/specs/2026-04-20-acknowledge-triage-category-design.md` to three skill files so Acknowledge becomes a first-class 5th triage category (peer to apply/dismiss/clarify/defer), with its stay-unresolved behavior documented consistently everywhere merges or review threads are discussed.

**Architecture:** Docs-only PR. No code changes. Three *skill* files get coordinated edits; the plan doc itself ships alongside as the audit trail. Each skill file is edited independently in its own task; a final cross-file verification task confirms the five-way triage framing and Acknowledge's stay-unresolved contract are consistent across the three files.

**Tech Stack:** Plain Markdown. Git. `gh` CLI.

**Branch:** `docs/implement-acknowledge-triage-category-2` (already created, based on `main` at `33a328a`).

**Repo:** `qubitrenegade/github-pr-review-loop`.

**Spec reference (authoritative):** `docs/superpowers/specs/2026-04-20-acknowledge-triage-category-design.md`. Every edit below cites the spec section that defines it.

---

## Task 1: SKILL.md — eight coordinated edits

**Files:**
- Modify: `skills/github-pr-review-loop/SKILL.md`

**Spec sections:** SKILL.md changes #1-#8

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "^description: Drives GitHub PRs" skills/github-pr-review-loop/SKILL.md
grep -n "^## The triage — apply, dismiss, clarify, or defer" skills/github-pr-review-loop/SKILL.md
grep -n "one of four dispositions: apply, dismiss, clarify, or defer" skills/github-pr-review-loop/SKILL.md
grep -n "Resolve each thread after replying" skills/github-pr-review-loop/SKILL.md
grep -n "Triage each comment (apply / dismiss / clarify / defer)" skills/github-pr-review-loop/SKILL.md
grep -n "zero new comments, repeats only, volume dried up, or user override" skills/github-pr-review-loop/SKILL.md
grep -n '^## Stop conditions' skills/github-pr-review-loop/SKILL.md
grep -n "User override — the maintainer says" skills/github-pr-review-loop/SKILL.md
```

Expected: every grep returns exactly one matching line. If any returns zero matches, stop — the spec's starting assumptions no longer hold against the current file. Re-read both the spec and the file before proceeding.

- [ ] **Step 2: Edit #1 — replace triage section heading**

Per spec SKILL.md change #1, replace the section heading:

> ## The triage — apply, dismiss, clarify, or defer

With:

> ## The triage — apply, dismiss, clarify, defer, or acknowledge

- [ ] **Step 3: Edit #2 — replace triage lead sentence**

Per spec SKILL.md change #2. The current sentence (on the line immediately after the triage heading) reads:

> Every Copilot inline comment is a claim. Verify the claim first, then triage it into one of four dispositions: apply, dismiss, clarify, or defer. Verification is step one for *every* disposition, not just Dismiss.

Replace with:

> Every Copilot inline comment is a claim. Verify the claim first, then triage it into one of five dispositions: apply, dismiss, clarify, defer, or acknowledge. Verification is step one for *every* disposition, not just Dismiss.

Use the Edit tool with the old and new full sentences. Note: the sentence is on a single line in the file; your `old_string` should be the exact single line (no manual line-wrapping).

- [ ] **Step 4: Edit #3 — append Acknowledge bullet after Defer**

Per spec SKILL.md change #3. Find the last paragraph of the Defer bullet — it ends with:

> `Defer` is a special case of `Apply` where the "apply" happens in a
> separate PR. Same discipline: evidence that the finding is real,
> explicit link to the follow-up so it isn't forgotten.

Immediately after that paragraph (before the `## After replying, resolve the conversation` heading), insert a blank line followed by this new `**Acknowledge**` bullet and its explanatory paragraph:

```markdown
**Acknowledge** — the finding is a vote from Copilot on a question that's explicitly the maintainer's call (typical on plan/spec PRs with open design questions embedded in the doc). Record the vote, don't treat it as authoritative, and **leave the thread unresolved** pending maintainer input:

> Vote recorded for option \<A/B/C> — this is a maintainer-authority decision; leaving the thread unresolved pending @\<maintainer>.

Unlike the other four dispositions, Acknowledge does not resolve the thread. That's intentional: an open design question is not done until a human answers it. This interacts with the merge gate — see "Before merging" / the complementary "zero unresolved threads" signal. Each Acknowledge thread blocks merge until the maintainer converts it into an Apply (accept the vote) or a Dismiss (overrule it).
```

Note: the `\<A/B/C>` and `\<maintainer>` use backslash escapes so the angle brackets render as literal text (not parsed as HTML). Keep the backslashes.

- [ ] **Step 5: Edit #4 — append Acknowledge-exception paragraph to "After replying, resolve the conversation"**

Per spec SKILL.md change #4. Find the existing final paragraph of the `## After replying, resolve the conversation` section — it ends with:

> For `Clarify`, resolve only after the reviewer answers and you've
> either Applied or Dismissed the answer. For `Defer`, resolve after
> filing the follow-up issue and linking it — the current PR's thread
> is closed because its disposition is settled, even if the fix lives
> elsewhere.

Immediately after that paragraph (before the `## How to re-trigger review after pushing fixes` heading), insert a blank line followed by:

```markdown
For `Acknowledge`, do not resolve. The thread intentionally stays open until the maintainer decides the underlying design question. Resolving early would make the PR look merge-ready when a design decision is actually still pending. Once the maintainer weighs in, convert the thread into an Apply (accept the vote, edit the plan/spec doc, cite SHA) or a Dismiss (overrule the vote with the maintainer's chosen alternative), and resolve as part of that follow-up action. See [references/triage-patterns.md](references/triage-patterns.md) under "Acknowledge" for the full pattern.
```

- [ ] **Step 6: Edit #5 — add mode-shift bullet to Stop conditions list**

Per spec SKILL.md change #5. The Stop conditions list currently ends with:

> - **User override — the maintainer says "stop".** Explicit review-loop
>   halt. Note: this is distinct from "user says merge," which is a
>   merge-authorization signal, not a stop signal (see Merge
>   authorization).

Append a new bullet immediately after (before the existing `See [references/stop-conditions.md]...` paragraph that follows the list):

```markdown
- **Copilot shifts from prose-bug finding to design-voting.** Interpret as "the prose has stabilised; the remaining work is a human decision." On plan/spec PRs, this often coincides with a round's findings being predominantly Acknowledge-class. See [references/stop-conditions.md](references/stop-conditions.md) under "Tertiary stop" for the detail.
```

- [ ] **Step 7: Edit #6 — update frontmatter `description:` field**

Per spec SKILL.md change #6. The YAML frontmatter at the top of the file currently reads:

> `description: Drives GitHub PRs through Copilot review to merge via disciplined triage (apply / dismiss / clarify / defer), empirical dismissal of hallucinations, GraphQL-based re-request, and concrete stop conditions. Use for a Copilot-reviewed PR that needs driving to merge, for parallel batches of related PRs, or when deciding whether a Copilot finding is real.`

Update the triage enumeration inside the parentheses from `apply / dismiss / clarify / defer` to `apply / dismiss / clarify / defer / acknowledge`. The full updated description should read:

> `description: Drives GitHub PRs through Copilot review to merge via disciplined triage (apply / dismiss / clarify / defer / acknowledge), empirical dismissal of hallucinations, GraphQL-based re-request, and concrete stop conditions. Use for a Copilot-reviewed PR that needs driving to merge, for parallel batches of related PRs, or when deciding whether a Copilot finding is real.`

- [ ] **Step 8: Edit #7 — update "The loop" steps 2 and 5**

Per spec SKILL.md change #7.

**Step 2 current:**
```
2. Triage each comment (apply / dismiss / clarify / defer).
```

**Step 2 new:**
```
2. Triage each comment (apply / dismiss / clarify / defer / acknowledge).
```

**Step 5 current:**
```
5. Post inline replies with commit SHAs / empirical dismissals /
   follow-up issue links. Resolve each thread after replying.
```

**Step 5 new:**
```
5. Post inline replies with commit SHAs / empirical dismissals /
   follow-up issue links. Resolve each thread after replying (**except Acknowledge threads, which stay unresolved pending maintainer decision — see "After replying, resolve the conversation"**).
```

Use the Edit tool twice (once per step). Match the exact indentation and line-wrapping of the original in `old_string`.

- [ ] **Step 9: Edit #8 — update "Before merging" opener stop-condition enumeration**

Per spec SKILL.md change #8. The three-gate opener at the top of `## Before merging: CI must be green` (the section's first paragraph, a blockquote) currently reads:

> > Merging requires three gates to clear: the Copilot review loop has converged (see Stop conditions — a stop condition has fired, whether that's zero new comments, repeats only, volume dried up, or user override), green CI (below), and user authorization (see Merge authorization). This section covers the CI gate; the other two have their own sections.

Replace the enumeration portion. The full updated blockquote should read:

> > Merging requires three gates to clear: the Copilot review loop has converged (see Stop conditions — a stop condition has fired, whether that's zero new comments, repeats only, volume dried up, user override, or a prose-to-design-voting mode shift on a plan/spec PR), green CI (below), and user authorization (see Merge authorization). This section covers the CI gate; the other two have their own sections.

- [ ] **Step 10: Verify edits landed**

Run:

```bash
grep -n "^## The triage — apply, dismiss, clarify, defer, or acknowledge" skills/github-pr-review-loop/SKILL.md
grep -n "one of five dispositions: apply, dismiss, clarify, defer, or acknowledge" skills/github-pr-review-loop/SKILL.md
grep -n "^\*\*Acknowledge\*\* — the finding is a vote from Copilot" skills/github-pr-review-loop/SKILL.md
grep -n "For \`Acknowledge\`, do not resolve" skills/github-pr-review-loop/SKILL.md
grep -n "Copilot shifts from prose-bug finding to design-voting" skills/github-pr-review-loop/SKILL.md
grep -n "apply / dismiss / clarify / defer / acknowledge" skills/github-pr-review-loop/SKILL.md
grep -n "prose-to-design-voting mode shift" skills/github-pr-review-loop/SKILL.md
grep -cn "apply / dismiss / clarify / defer)" skills/github-pr-review-loop/SKILL.md
grep -cn "apply, dismiss, clarify, or defer" skills/github-pr-review-loop/SKILL.md
```

Expected:
- First seven greps: one matching line each.
- `apply / dismiss / clarify / defer / acknowledge` grep: at least 2 matches (frontmatter + The-loop step 2).
- Last two greps (counts of old four-way enumerations): `0` each. If either is >0, the old text is still in the file — re-check the failing edit.

- [ ] **Step 11: Commit**

```bash
git add skills/github-pr-review-loop/SKILL.md
git commit -m "docs(skill): Acknowledge triage category + mode-shift stop signal

Per docs/superpowers/specs/2026-04-20-acknowledge-triage-category-design.md (SKILL.md changes #1-#8):

- Triage section becomes 5-way: heading, lead sentence, new Acknowledge bullet
- After-replying section: Acknowledge-exception paragraph (stay unresolved)
- Stop conditions list: new mode-shift bullet
- Frontmatter description: 4-way -> 5-way enumeration
- The loop steps 2 (triage enumeration) and 5 (Resolve-except-Acknowledge)
- Before-merging opener: add mode-shift to the exhaustive-looking enumeration"
```

---

## Task 2: triage-patterns.md — six coordinated edits

**Files:**
- Modify: `skills/github-pr-review-loop/references/triage-patterns.md`

**Spec sections:** triage-patterns.md changes #1-#6

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "^# Triage patterns — apply, dismiss, clarify, defer" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Contents" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Verify first" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Defer" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Resolve the thread after replying" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Batching multiple findings into one push" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "Write triage decisions next to each (apply / dismiss / clarify / defer)" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "Correct but out-of-scope → \*\*Defer\*\*" skills/github-pr-review-loop/references/triage-patterns.md
```

Expected: all 8 greps return exactly one matching line.

- [ ] **Step 2: Edit #1 — update file title line**

Per spec triage-patterns.md change #1. The first line of the file currently reads:

> # Triage patterns — apply, dismiss, clarify, defer

Replace with:

> # Triage patterns — apply, dismiss, clarify, defer, acknowledge

- [ ] **Step 3: Edit #2 — insert Acknowledge entry in Contents TOC**

Per spec triage-patterns.md change #2. The Contents list currently has (among other entries):

```
- Defer — out-of-scope but valid, file a follow-up issue
- Resolve the thread after replying
```

Insert a new entry between those two lines so the Contents becomes:

```
- Defer — out-of-scope but valid, file a follow-up issue
- Acknowledge — record reviewer vote on maintainer-authority decisions, leave thread unresolved
- Resolve the thread after replying
```

- [ ] **Step 4: Edit #3 — insert new `## Acknowledge` section**

Per spec triage-patterns.md change #3. Find the end of the `## Defer` section (its last paragraph ends before the `## Resolve the thread after replying` heading). Insert a blank line, then the full Acknowledge section, then another blank line before the Resolve heading. Full content to insert:

```markdown
## Acknowledge

The finding is a vote from Copilot on a question that's explicitly the maintainer's call — typically on plan or spec PRs with open design questions (A/B/C choice questions) embedded in the doc. Record the vote; don't treat it as authoritative; leave the thread unresolved until the maintainer weighs in.

**Template:**

> Vote recorded for option \<A/B/C> — this is a maintainer-authority decision; leaving the thread unresolved pending @\<maintainer>.

The `@` is plain (not inside backticks) so GitHub fires a mention notification when the template is used in an actual PR reply with a real username. The backslash escapes the angle brackets so the placeholder renders literally in this doc.

**Example (real):**

On the clickwork Sigstore plan PR #97 round 3, after the prose had stabilised, Copilot returned votes on each of the plan's six open design questions (Q1-Q6) with reasoned A/B/C justifications. Each vote got:

> Vote recorded: option B (keyless cosign). Reasoning noted. This is a maintainer-authority decision — leaving the thread unresolved pending `@qubitrenegade`.

(Backticks around `@qubitrenegade` are intentional *in this reference doc* to avoid GitHub firing a mention notification every time the doc is rendered. In an actual PR reply you write the mention in plain text — no backticks — so the notification fires and the maintainer gets pinged.)

Threads stayed open until the maintainer reviewed each vote and either accepted the reasoning (thread becomes an Apply — edit the plan/spec doc to lock the choice) or overruled with their own pick (thread becomes a Dismiss of the vote, Apply of the maintainer's choice).

**When NOT to use Acknowledge:**

- The finding is a bug claim, not a vote. Those are apply/dismiss.
- The question has an objectively correct answer that verification can establish. Those are apply/dismiss.
- The decision is a preference *you* can reasonably make. Don't punt implementation choices to the maintainer via Acknowledge.
- The PR isn't a plan/spec PR. Design decisions rarely live in implementation PRs; if Copilot is voting on one there, the PR probably should have been preceded by a plan or spec PR. Flag to the maintainer rather than accumulating Acknowledge threads.

**Why the thread stays unresolved:**

An open design question is not done until a human answers it. The "zero unresolved threads" merge signal (see stop-conditions.md) treats Acknowledge threads as blocking on purpose — a plan or spec PR with open votes is one that hasn't locked its design yet, and merging it is premature. When the maintainer decides, they (or you, on their behalf) either edit the plan/spec doc to reflect the choice and convert the thread to an Apply-with-SHA, or reply with the counter-decision and convert the thread to a Dismiss. Either way, the thread resolves as part of making the decision, not independent of it.

**The mode-shift signal:**

When a Copilot round's findings are predominantly Acknowledge-class, that's a stop signal on its own (see stop-conditions.md under "Tertiary stop"). It means the prose has stabilised and the remaining work is the human decision — the review loop has done what it can; maintainer time is the next bottleneck, not another Copilot round.
```

- [ ] **Step 5: Edit #4 — update `## Verify first` mapping**

Per spec triage-patterns.md change #4. The `## Verify first` section currently has a 4-way bullet list that ends with:

> - Correct but out-of-scope → **Defer** with follow-up issue.

Append a 5th bullet immediately after (before the blank line that separates the list from the "Applying without verifying..." paragraph):

```markdown
- Not about claim truth at all — Copilot is voting on a maintainer-authority decision → **Acknowledge** (leave the thread unresolved pending maintainer decision; this is a different axis from the four above — see the Acknowledge section below).
```

Then find the existing paragraph that starts "Applying without verifying is the more subtle trap..." and ends "See the Evidence Checklist (below) for commands to run per claim type." Immediately after that paragraph (before the next `## Evidence checklist` heading), insert a blank line and a new paragraph:

```markdown
Four of these dispositions (apply / dismiss / clarify / defer) sort findings by whether the claim is true, false, ambiguous, or out-of-scope. **Acknowledge is on a different axis**: it handles findings where the reviewer is voting on a question that isn't theirs to decide. Plan and spec PRs with open design questions are where this shows up — Copilot reads the question, offers an A/B/C vote with reasoning, and that vote is neither bug-fixable nor wrong, but also not authoritative. See the Acknowledge section below for the full pattern.
```

- [ ] **Step 6: Edit #5 — update `## Resolve the thread after replying` section**

Per spec triage-patterns.md change #5. Find the existing `**When NOT to resolve:**` bullet list near the end of that section. Its last bullet is:

> - When a human reviewer is still active on the thread. Let them
>   resolve it themselves; don't stomp on their conversation.

Immediately after that last bullet (before the next `## Evidence checklist` heading — NOTE: after Edit #2 of the previous implementation, Evidence checklist was moved up; the section that now follows is `## Apply`. Verify by scanning — the correct place is at the end of the `## Resolve the thread after replying` section, just before whichever section follows it). Insert a blank line and:

```markdown
**Acknowledge is the sustained exception.** Unlike the other four dispositions, Acknowledge threads intentionally stay unresolved until the maintainer decides the underlying question. Resolving an Acknowledge thread early defeats the "open design question" signal — it makes the PR look merge-ready when a design decision is actually still pending. Only resolve once the maintainer has weighed in and you've converted the thread into an Apply (decision accepted → plan edited) or Dismiss (decision overruled).
```

- [ ] **Step 7: Edit #6 — update Batching section's slash-form enumeration**

Per spec triage-patterns.md change #6. Find the bullet in the `## Batching multiple findings into one push` section that currently reads:

> - Write triage decisions next to each (apply / dismiss / clarify / defer).

Replace with:

> - Write triage decisions next to each (apply / dismiss / clarify / defer / acknowledge).

- [ ] **Step 8: Verify edits landed**

Run:

```bash
grep -n "^# Triage patterns — apply, dismiss, clarify, defer, acknowledge" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^- Acknowledge — record reviewer vote on maintainer-authority" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Acknowledge" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "Not about claim truth at all" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "\*\*Acknowledge is on a different axis\*\*" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "\*\*Acknowledge is the sustained exception\.\*\*" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "apply / dismiss / clarify / defer / acknowledge" skills/github-pr-review-loop/references/triage-patterns.md
grep -cn "apply / dismiss / clarify / defer)" skills/github-pr-review-loop/references/triage-patterns.md
```

Expected:
- First six greps: one matching line each.
- `apply / dismiss / clarify / defer / acknowledge` grep: at least one match (the Batching section bullet).
- Last grep (count of old four-way slash-form): `0`. If >0, the Batching-section edit didn't land.

- [ ] **Step 9: Commit**

```bash
git add skills/github-pr-review-loop/references/triage-patterns.md
git commit -m "docs(triage): add Acknowledge section + two-axis Verify-first framing

Per docs/superpowers/specs/2026-04-20-acknowledge-triage-category-design.md (triage-patterns.md changes #1-#6):

- Title line: 4-way -> 5-way enumeration
- Contents TOC: new Acknowledge entry between Defer and Resolve
- New ## Acknowledge section with template, real example, when-NOT-to-use, why-unresolved, mode-shift signal
- Verify-first mapping: add Acknowledge bullet + two-axis clarifying paragraph (truth-based vs authority-based)
- Resolve-the-thread section: Acknowledge-is-sustained-exception paragraph
- Batching section: slash-form enumeration updated to 5-way"
```

---

## Task 3: stop-conditions.md — three coordinated edits

**Files:**
- Modify: `skills/github-pr-review-loop/references/stop-conditions.md`

**Spec sections:** stop-conditions.md changes #1 and #2 (with sub-edits 2a/2b)

- [ ] **Step 1: Verify current file state matches spec's before-text**

Run:

```bash
grep -n "^## Complement: zero unresolved conversation threads" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "^## Tertiary stop: volume drying up" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "Humans skimming the PR can trust that nothing slipped" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "If this count is >0" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "gets triaged (apply / dismiss / clarify / defer)" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "This is different from \"ignore round-4+ comments\"" skills/github-pr-review-loop/references/stop-conditions.md
```

Expected: all 6 greps return exactly one matching line.

- [ ] **Step 2: Edit #1a — append "Acknowledge threads count as unresolved" paragraph to the Complement section**

Per spec stop-conditions.md change #1. Find the existing paragraph in `## Complement: zero unresolved conversation threads` that ends with "Humans skimming the PR can trust that nothing slipped." Immediately after that paragraph (before the "If this count is >0..." paragraph that follows), insert a blank line and:

```markdown
**Acknowledge threads count as unresolved, intentionally.** On plan or spec PRs with open design questions, Acknowledge threads (where Copilot voted on a maintainer-authority decision — see [triage-patterns.md](triage-patterns.md) under "Acknowledge") stay unresolved until the maintainer decides. These are not "forgotten to resolve" — they are actively signaling "a design question is still open." The merge gate treats them the same as any other unresolved thread, which is the forcing function: the PR doesn't merge until the design is locked. If the unresolved count is N and all N are Acknowledge threads, the gate is correctly blocking — the remedy is maintainer decisions, not clicking Resolve.
```

- [ ] **Step 3: Edit #1b — append Acknowledge-exception sentence to the "If this count is >0..." paragraph**

Per spec stop-conditions.md change #1 (second part). Find the existing paragraph that starts "If this count is >0..." — it currently ends somewhere around "...Either resolve them now (if they were addressed and you just forgot) or go back and act on them (if they're actually pending)." At the end of that paragraph, append this sentence:

```
**Exception:** Acknowledge threads on plan or spec PRs are pending maintainer decision, not forgotten — see the note above.
```

The sentence joins the existing paragraph (no blank line before it). Use the Edit tool with the existing paragraph's last sentence as `old_string` and `<existing last sentence> <new sentence>` as `new_string`.

- [ ] **Step 4: Edit #2a — update the slash-form enumeration in Tertiary stop**

Per spec stop-conditions.md change #2a. In the `## Tertiary stop: volume drying up` section, find the paragraph that contains:

> Every comment still gets triaged (apply / dismiss / clarify / defer). The stop decision is about

Update the slash-form enumeration inside the parentheses from `apply / dismiss / clarify / defer` to `apply / dismiss / clarify / defer / acknowledge`. The full updated sentence reads:

> This is different from "ignore round-4+ comments". Every comment still gets triaged (apply / dismiss / clarify / defer / acknowledge). The stop decision is about whether to wait for another round, not whether to process comments already on the PR.

- [ ] **Step 5: Edit #2b — append Mode-shift paragraph to Tertiary stop**

Per spec stop-conditions.md change #2b. After the paragraph you just updated in Step 4 (the one starting "This is different from..."), and before the next `## User override of the review loop` heading, insert a blank line and:

```markdown
**Mode-shift sub-signal.** On plan or spec PRs, "volume drying up" often has a characteristic shape: the first few rounds surface prose-level issues (factual errors, stale references, internal inconsistencies) which get applied or dismissed normally. Once the prose stabilises, Copilot shifts modes and starts voting on the open design questions embedded in the doc — the round is no longer surfacing bugs, it's surfacing Acknowledge-class findings (see [triage-patterns.md](triage-patterns.md) under "Acknowledge"). That mode shift is itself a stop signal: the doc is substantively clean; the remaining work is the maintainer's decision, not another Copilot round. When a round's findings are predominantly Acknowledge, the review loop has done what it can, and what unblocks progress next is maintainer time, not another re-request.
```

- [ ] **Step 6: Verify edits landed**

Run:

```bash
grep -n "\*\*Acknowledge threads count as unresolved, intentionally\.\*\*" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "\*\*Exception:\*\* Acknowledge threads on plan or spec PRs" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "apply / dismiss / clarify / defer / acknowledge" skills/github-pr-review-loop/references/stop-conditions.md
grep -n "\*\*Mode-shift sub-signal\.\*\*" skills/github-pr-review-loop/references/stop-conditions.md
grep -cn "apply / dismiss / clarify / defer)" skills/github-pr-review-loop/references/stop-conditions.md
```

Expected:
- First four greps: one matching line each.
- Last grep (count of old four-way slash-form): `0`. If >0, the Edit #2a didn't land.

- [ ] **Step 7: Commit**

```bash
git add skills/github-pr-review-loop/references/stop-conditions.md
git commit -m "docs(stop-conditions): Acknowledge threads block merge + mode-shift sub-signal

Per docs/superpowers/specs/2026-04-20-acknowledge-triage-category-design.md (stop-conditions.md changes #1 and #2):

- Complement section: Acknowledge threads count as unresolved (intentional block-the-merge behavior) + Exception note on the 'if >0' paragraph
- Tertiary stop: slash-form enumeration 4-way -> 5-way (edit #2a); new Mode-shift sub-signal paragraph (edit #2b)"
```

---

## Task 4: Cross-file verification sweep

**Files (read only):**
- `skills/github-pr-review-loop/SKILL.md`
- `skills/github-pr-review-loop/references/triage-patterns.md`
- `skills/github-pr-review-loop/references/stop-conditions.md`

**Spec section:** Verification.

- [ ] **Step 1: Read-through consistency check**

Open all three files in order: SKILL.md → triage-patterns.md → stop-conditions.md. Read each top to bottom.

Confirm each of these holds:

- The five-way triage enumeration appears consistently: SKILL.md (triage heading + lead sentence + frontmatter + The-loop step 2), triage-patterns.md (title + Contents + Verify-first mapping + Batching section), stop-conditions.md (Tertiary stop body).
- Acknowledge's stay-unresolved contract is described consistently in all four places: SKILL.md's triage body Acknowledge bullet, SKILL.md's After-replying Acknowledge paragraph, triage-patterns.md's `## Acknowledge` section, triage-patterns.md's Resolve-the-thread exception note, and stop-conditions.md's Complement section note. They don't contradict each other.
- The mode-shift signal appears in both triage-patterns.md (Acknowledge section's final subheading) AND stop-conditions.md (Tertiary stop's Mode-shift paragraph) AND SKILL.md (Stop conditions list bullet + Before-merging opener enumeration). Four places, consistent framing.
- No section contradicts another. If something reads as contradictory, stop and fix in the corresponding task's file before proceeding.

- [ ] **Step 2: Cross-reference link check**

Run:

```bash
# triage-patterns.md's Acknowledge section references stop-conditions.md's Tertiary stop
grep -Ecn "stop-conditions\.md.*Tertiary stop|stop-conditions\.md.*Acknowledge" skills/github-pr-review-loop/references/triage-patterns.md

# stop-conditions.md's mode-shift paragraph references triage-patterns.md's Acknowledge
grep -cn "triage-patterns.md.*Acknowledge" skills/github-pr-review-loop/references/stop-conditions.md

# SKILL.md's Acknowledge bullet + After-replying Acknowledge paragraph reference triage-patterns.md's Acknowledge section
grep -cn "triage-patterns.md" skills/github-pr-review-loop/SKILL.md
```

Expected: all three greps return a count ≥1. Zero count = orphan reference; find and fix.

- [ ] **Step 3: Grep sweep for old four-way enumerations**

Run:

```bash
# Both old four-way forms should be fully replaced
echo "=== comma-form 'apply, dismiss, clarify, or defer' (expect 0):"
grep -rn "apply, dismiss, clarify, or defer" skills/github-pr-review-loop/ || echo "  clean"

echo "=== slash-form 'apply / dismiss / clarify / defer)' (expect 0):"
grep -rn "apply / dismiss / clarify / defer)" skills/github-pr-review-loop/ || echo "  clean"

echo "=== title-form 'apply, dismiss, clarify, defer' without 'or' or 'acknowledge' (expect 0):"
grep -rn "^# Triage patterns — apply, dismiss, clarify, defer$" skills/github-pr-review-loop/ || echo "  clean"

# New five-way forms should appear in the expected places
echo "=== five-way comma-form (expect >=2: SKILL.md heading + SKILL.md lead):"
grep -Ern "apply, dismiss, clarify, defer, or acknowledge|apply, dismiss, clarify, defer, acknowledge" skills/github-pr-review-loop/

echo "=== five-way slash-form (expect >=4: SKILL frontmatter, SKILL loop step 2, triage-patterns Batching, stop-conditions Tertiary):"
grep -rn "apply / dismiss / clarify / defer / acknowledge" skills/github-pr-review-loop/
```

Every old-form grep should either report no matches or trigger the "clean" fallback echo. Every new-form grep should hit in the expected locations. If any old form remains, trace to which task's file owns that line and go back to fix.

- [ ] **Step 4: Commit verification fixes (only if Steps 1-3 surfaced anything that needed fixing)**

If verification was clean, no commit is needed for this task. If anything was fixed, the fix commit goes to whichever file was wrong (re-run the commit pattern from Tasks 1-3 for that file).

---

## Task 5: Open PR + run Copilot review loop

**Scope:** Main session, not subagent. The review loop needs conversational decision-making (triage calls, merge authorization from user) that doesn't delegate cleanly.

- [ ] **Step 1: Push branch**

```bash
git push -u origin docs/implement-acknowledge-triage-category-2
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "docs: Acknowledge triage category + mode-shift stop signal (#2)" --body "$(cat <<'EOF'
## Summary

Implementation PR for the spec merged at 33a328a (PR #11). Addresses issue #2.

Four files ship in this PR: three **skill files** carrying the framing edits, plus the **plan document** as the audit trail for what changed and why.

Skill files edited:

- \`skills/github-pr-review-loop/SKILL.md\` — 5-way triage (heading, lead, new Acknowledge bullet, frontmatter description), After-replying Acknowledge-exception paragraph, The-loop steps 2 and 5, Stop conditions mode-shift bullet, Before-merging opener's enumeration updated.
- \`skills/github-pr-review-loop/references/triage-patterns.md\` — title line, Contents TOC, new \`## Acknowledge\` section, Verify-first mapping updated to two-axis model (truth-based dispositions vs authority-based Acknowledge), Resolve-thread Acknowledge-is-sustained-exception note, Batching slash-form enumeration updated.
- \`skills/github-pr-review-loop/references/stop-conditions.md\` — Complement section: Acknowledge-threads-count-as-unresolved note + Exception sentence on the if-count->0 paragraph; Tertiary stop: slash-form enumeration updated + Mode-shift sub-signal paragraph.

Plan doc:

- \`docs/superpowers/plans/2026-04-20-acknowledge-triage-category-implementation.md\` — the implementation plan followed to make the three skill edits above.

## Net-new guidance (not previously documented)

- **Acknowledge triage category** — 5th category for when Copilot votes on open design questions in plan/spec PRs. Thread stays unresolved pending maintainer decision; the merge gate treats it as blocking on purpose.
- **Mode-shift stop signal** — when Copilot shifts from prose-bug finding to design-voting, the prose has stabilised and maintainer time (not another Copilot round) is the next bottleneck.
- **Two-axis triage model** — the original four dispositions sort findings by claim truth; Acknowledge is on a separate axis (reviewer authority). The Verify-first section now documents this distinction.

## Dogfooding

This PR was built by running the github-pr-review-loop skill against its own spec PR (#11), which saw 7 Copilot rounds (2/3/4/1/1/2/0 findings) before converging. The round-3 internal-consistency spiral caught 4 places where the spec under-covered SKILL.md edits (frontmatter, The-loop numbered steps, Before-merging enumeration, Verify-first mapping) — exactly the kind of cascade that would otherwise show up as expensive findings in this implementation PR.

## Out of scope

Each gets its own later PR: #4 (reply+resolve helper), #6 (outside-the-repo blockers), #7 (worktree cleanup).

## Test plan

- [ ] Copilot review loop run on this PR (dogfood — recursively, with the new Acknowledge category itself in play)
- [ ] Cross-file three-way framing consistency audit after any review-loop edits land
- [ ] Merge after Copilot signal exhausts + maintainer authorization (per the three-gate model)

Refs #2
Spec: \`docs/superpowers/specs/2026-04-20-acknowledge-triage-category-design.md\`
Plan: \`docs/superpowers/plans/2026-04-20-acknowledge-triage-category-implementation.md\`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Request Copilot review**

```bash
REPO="qubitrenegade/github-pr-review-loop"
PR_NUM="<number-from-gh-pr-create>"
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

Handoff to the github-pr-review-loop skill's normal drill: wait for Copilot, verify-first + triage each finding (apply / dismiss / clarify / defer / **acknowledge**), reply + resolve per thread, re-request, repeat until a stop condition fires. Note: this PR itself introduces Acknowledge; if Copilot's feedback on this PR is ever a vote on a design choice we left open, the new category applies to itself. On a well-scoped implementation PR it shouldn't come up (the design was locked in the spec PR), but stay alert to the pattern.

Stop condition + user merge authorization → merge.

---

## Self-review notes

- **Spec coverage:** Every numbered edit in the spec maps to a named step in Tasks 1-3: SKILL.md #1-#8 → Task 1 steps 2-9; triage-patterns.md #1-#6 → Task 2 steps 2-7; stop-conditions.md #1/#2a/#2b → Task 3 steps 2-5. No spec requirement is orphaned.
- **Placeholder scan:** No TBDs, TODOs, "implement later" items. Every edit step shows exact before-text and after-text. Template placeholders (`\<A/B/C>`, `@\<maintainer>`, `@<maintainer>`) are intentional and explained in the spec; they render as literal angle brackets in Markdown and instruct the implementer to keep them as-is.
- **Type consistency:** Section heading names used consistently across tasks. `## Acknowledge` in triage-patterns.md, `## Merge authorization` / `## Before merging: CI must be green` references match what landed in the previous #5+#3 PR. Cross-references use matching heading text.
- **No new primitives** — this is re-parenting + net-new guidance (the Acknowledge category, mode-shift signal, two-axis model) per spec. No new files created except the plan doc itself.
