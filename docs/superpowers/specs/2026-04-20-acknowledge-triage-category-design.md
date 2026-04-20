# Acknowledge triage category — design

**Date:** 2026-04-20
**Issue:** [#2](https://github.com/qubitrenegade/github-pr-review-loop/issues/2)
**Type:** Docs / framing PR — no code changes.

## Problem

On a real plan-PR use of the `github-pr-review-loop` skill (clickwork PR #97, Sigstore signing plan), Copilot exhibited a pattern the skill doesn't currently handle cleanly:

- Rounds 1-2: Copilot surfaced prose-level issues (factual errors, stale references, internal inconsistencies) which the agent applied or dismissed per the existing four-way triage.
- Round 3: after the prose had stabilised, Copilot shifted modes and started **voting on the open A/B/C design questions** embedded in the plan doc, with reasoned justifications for each pick.

Those votes don't fit cleanly into apply / dismiss / clarify / defer:

- Not a bug to "apply" (no fix exists).
- Not wrong to "dismiss" (the vote's reasoning may be correct; it's just not Copilot's decision).
- Not ambiguous to "clarify" (nothing is unclear — it's a design choice).
- Not out-of-scope to "defer" (it's entirely in-scope for a plan PR; a human decision is how the question gets resolved).

In the live use the agent handled this by posting "acknowledged, flagging to @maintainer" replies per thread and leaving each unresolved, but that pattern wasn't written down anywhere. This spec adds it explicitly.

There's a companion observation worth documenting too: **Copilot tends to shift from prose-bug finding to design-voting when the prose stabilises.** That mode shift is itself a useful stop-loop signal — the plan doc is substantively clean; the remaining work is the maintainer's call, not another Copilot round.

## Design

### Scope

Bundled docs PR touching three files:

- `skills/github-pr-review-loop/SKILL.md` — triage section becomes five-way (add Acknowledge), update lead sentence + heading, add mode-shift bullet to the Stop conditions list.
- `skills/github-pr-review-loop/references/triage-patterns.md` — new `## Acknowledge` section with template and real example, TOC update, title-line update, Resolve-the-thread section gets an "Acknowledge is the sustained exception" note.
- `skills/github-pr-review-loop/references/stop-conditions.md` — expand "Complement: zero unresolved conversation threads" to explicitly note Acknowledge threads count as unresolved (by design), and expand "Tertiary stop: volume drying up" with the mode-shift sub-signal.

No code changes. No new primitives.

**Out of scope** (each gets its own later PR): #4 (reply+resolve helper), #6 (outside-the-repo blockers), #7 (worktree cleanup).

### Design choices (locked in during brainstorm)

- **Top-level 5th category**, not a sub-pattern under Clarify or Defer. Acknowledge is conceptually distinct — the other four dispositions all assume the reviewer has authority to make a claim. Acknowledge handles the case where the reviewer's input is a vote on someone else's decision. That's a new axis (reviewer authority), so it gets its own slot.
- **Mode-shift signal lives in both places** — triage-patterns.md's Acknowledge section mentions it (as "when Acknowledge findings dominate a round, that's the stop signal") and stop-conditions.md's Tertiary stop carries the detail.
- **Acknowledge threads block the merge signal** — the "zero unresolved threads" gate treats them as unresolved. Rationale: a plan PR with open design questions is a plan that hasn't locked its design; merging it is premature. The discipline forces maintainer decisions to land before the plan merges. On non-plan PRs Acknowledge shouldn't happen in the first place (if Copilot is voting on a design question in an implementation PR, the PR probably should have been preceded by a plan PR), so the block-the-signal rule doesn't hurt there.

### SKILL.md changes

#### 1. Update triage section heading

Current:

> ## The triage — apply, dismiss, clarify, or defer

New:

> ## The triage — apply, dismiss, clarify, defer, or acknowledge

#### 2. Update triage lead sentence

Current:

> Every Copilot inline comment is a claim. Verify the claim first, then triage it into one of four dispositions: apply, dismiss, clarify, or defer. Verification is step one for *every* disposition, not just Dismiss.

New:

> Every Copilot inline comment is a claim. Verify the claim first, then triage it into one of five dispositions: apply, dismiss, clarify, defer, or acknowledge. Verification is step one for *every* disposition, not just Dismiss.

#### 3. Add `**Acknowledge**` bullet after the Defer bullet

Append after the existing "`Defer` is a special case of `Apply`..." paragraph (the last paragraph of the Defer bullet):

```markdown
**Acknowledge** — the finding is a vote from Copilot on a question that's explicitly the maintainer's call (typical on plan/spec PRs with open design questions embedded in the doc). Record the vote, don't treat it as authoritative, and **leave the thread unresolved** pending maintainer input:

> Vote recorded for option <A/B/C> — this is a maintainer-authority decision; leaving the thread unresolved pending @\<maintainer>.

Unlike the other four dispositions, Acknowledge does not resolve the thread. That's intentional: an open design question is not done until a human answers it. This interacts with the merge gate — see "Before merging" / the complementary "zero unresolved threads" signal. Each Acknowledge thread blocks merge until the maintainer converts it into an Apply (accept the vote) or a Dismiss (overrule it).
```

Note on the `@\<maintainer>` rendering: the template uses a plain `@` (not inside backticks) so that when someone copy-pastes and substitutes a real username, GitHub fires the mention notification. The backslash before `<maintainer>` is a Markdown escape to render the angle brackets literally without GitHub trying to parse them as HTML. In an actual PR reply you would write `@qubitrenegade` with no backticks and no backslash.

#### 4. Update "After replying, resolve the conversation" section

SKILL.md currently has a section titled `## After replying, resolve the conversation` (at line 70+ in the current file) that prescribes resolving every thread after replying, with a final paragraph covering the Clarify and Defer timing. Without an Acknowledge-exception note here, SKILL.md becomes self-contradictory after the implementation PR: the triage body says Acknowledge stays unresolved, but the Resolve section says resolve everything.

Append a new paragraph after the existing final paragraph (the one that ends with "the current PR's thread is closed because its disposition is settled, even if the fix lives elsewhere."):

```markdown
For `Acknowledge`, do not resolve. The thread intentionally stays open until the maintainer decides the underlying design question. Resolving early would make the PR look merge-ready when a design decision is actually still pending. Once the maintainer weighs in, convert the thread into an Apply (accept the vote, edit the plan, cite SHA) or a Dismiss (overrule the vote with the maintainer's chosen alternative), and resolve as part of that follow-up action. See [references/triage-patterns.md](references/triage-patterns.md) under "Acknowledge" for the full pattern.
```

#### 5. Add mode-shift bullet to the Stop conditions list

Currently the Stop conditions list has four bullets (zero new, repeats, volume drying, user override). Add a fifth:

```markdown
- **Copilot shifts from prose-bug finding to design-voting.** Interpret as "the prose has stabilised; the remaining work is a human decision." On plan/spec PRs, this often coincides with a round's findings being predominantly Acknowledge-class. See [references/stop-conditions.md](references/stop-conditions.md) under "Tertiary stop" for the detail.
```

### triage-patterns.md changes

#### 1. Update file title line

Current:

> # Triage patterns — apply, dismiss, clarify, defer

New:

> # Triage patterns — apply, dismiss, clarify, defer, acknowledge

#### 2. Update Contents TOC

Insert between the `Defer` entry and the `Resolve the thread after replying` entry:

```
- Acknowledge — record reviewer vote on maintainer-authority decisions, leave thread unresolved
```

#### 3. New `## Acknowledge` section

Insert between the `## Defer` section (end of its body) and the `## Resolve the thread after replying` section (heading). Full content:

```markdown
## Acknowledge

The finding is a vote from Copilot on a question that's explicitly the maintainer's call — typically on plan or spec PRs with open design questions (A/B/C choice questions) embedded in the doc. Record the vote; don't treat it as authoritative; leave the thread unresolved until the maintainer weighs in.

**Template:**

> Vote recorded for option <A/B/C> — this is a maintainer-authority decision; leaving the thread unresolved pending @\<maintainer>.

The `@` is plain (not inside backticks) so GitHub fires a mention notification when the template is used in an actual PR reply with a real username. The backslash escapes the angle brackets so the placeholder renders literally in this doc.

**Example (real):**

On the clickwork Sigstore plan PR #97 round 3, after the prose had stabilised, Copilot returned votes on each of the plan's six open design questions (Q1-Q6) with reasoned A/B/C justifications. Each vote got:

> Vote recorded: option B (keyless cosign). Reasoning noted. This is a maintainer-authority decision — leaving the thread unresolved pending `@qubitrenegade`.

(Backticks around `@qubitrenegade` are intentional *in this reference doc* to avoid GitHub firing a mention notification every time the doc is rendered. In an actual PR reply you write the mention in plain text — no backticks — so the notification fires and the maintainer gets pinged.)

Threads stayed open until the maintainer reviewed each vote and either accepted the reasoning (thread becomes an Apply — edit the plan to lock the choice) or overruled with their own pick (thread becomes a Dismiss of the vote, Apply of the maintainer's choice).

**When NOT to use Acknowledge:**

- The finding is a bug claim, not a vote. Those are apply/dismiss.
- The question has an objectively correct answer that verification can establish. Those are apply/dismiss.
- The decision is a preference *you* can reasonably make. Don't punt implementation choices to the maintainer via Acknowledge.
- The PR isn't a plan/spec PR. Design decisions rarely live in implementation PRs; if Copilot is voting on one there, the PR probably should have been preceded by a plan PR. Flag to the maintainer rather than accumulating Acknowledge threads.

**Why the thread stays unresolved:**

An open design question is not done until a human answers it. The "zero unresolved threads" merge signal (see stop-conditions.md) treats Acknowledge threads as blocking on purpose — a plan PR with open votes is a plan that hasn't locked its design yet, and merging it is premature. When the maintainer decides, they (or you, on their behalf) either edit the plan to reflect the choice and convert the thread to an Apply-with-SHA, or reply with the counter-decision and convert the thread to a Dismiss. Either way, the thread resolves as part of making the decision, not independent of it.

**The mode-shift signal:**

When a Copilot round's findings are predominantly Acknowledge-class, that's a stop signal on its own (see stop-conditions.md under "Tertiary stop"). It means the prose has stabilised and the remaining work is the human decision — the review loop has done what it can; maintainer time is the next bottleneck, not another Copilot round.
```

#### 4. Update "Resolve the thread after replying" section

After the existing `**When NOT to resolve:**` bullet list (the one that ends with "Let them resolve it themselves; don't stomp on their conversation."), append a new paragraph:

```markdown
**Acknowledge is the sustained exception.** Unlike the other four dispositions, Acknowledge threads intentionally stay unresolved until the maintainer decides the underlying question. Resolving an Acknowledge thread early defeats the "open design question" signal — it makes the PR look merge-ready when a design decision is actually still pending. Only resolve once the maintainer has weighed in and you've converted the thread into an Apply (decision accepted → plan edited) or Dismiss (decision overruled).
```

### stop-conditions.md changes

#### 1. Expand "Complement: zero unresolved conversation threads" section

After the existing paragraph ending with "Humans skimming the PR can trust that nothing slipped." (the paragraph that defines what zero unresolved means), insert a new paragraph:

```markdown
**Acknowledge threads count as unresolved, intentionally.** On plan or spec PRs with open design questions, Acknowledge threads (where Copilot voted on a maintainer-authority decision — see [triage-patterns.md](triage-patterns.md) under "Acknowledge") stay unresolved until the maintainer decides. These are not "forgotten to resolve" — they are actively signaling "a design question is still open." The merge gate treats them the same as any other unresolved thread, which is the forcing function: the plan doesn't merge until the design is locked. If the unresolved count is N and all N are Acknowledge threads, the gate is correctly blocking — the remedy is maintainer decisions, not clicking Resolve.
```

Also update the existing "If this count is >0..." paragraph (which currently says "Either resolve them now (if they were addressed and you just forgot) or go back and act on them") by appending a sentence:

```
**Exception:** Acknowledge threads on plan PRs are pending maintainer decision, not forgotten — see the note above.
```

#### 2. Expand "Tertiary stop: volume drying up" section

Append a new paragraph after the existing `This is different from "ignore round-4+ comments"...` paragraph (the last paragraph of the section before `## User override of the review loop`):

```markdown
**Mode-shift sub-signal.** On plan or spec PRs, "volume drying up" often has a characteristic shape: the first few rounds surface prose-level issues (factual errors, stale references, internal inconsistencies) which get applied or dismissed normally. Once the prose stabilises, Copilot shifts modes and starts voting on the open design questions embedded in the doc — the round is no longer surfacing bugs, it's surfacing Acknowledge-class findings (see [triage-patterns.md](triage-patterns.md) under "Acknowledge"). That mode shift is itself a stop signal: the plan doc is substantively clean; the remaining work is the maintainer's decision, not another Copilot round. When a round's findings are predominantly Acknowledge, the review loop has done what it can, and what unblocks progress next is maintainer time, not another re-request.
```

## Verification

Docs-only PR; "testing" means:

1. **Read-through check** — read all three files top-to-bottom after edits. Confirm the five-way triage framing is consistent across SKILL.md (heading + lead sentence + body) and triage-patterns.md (title + Contents + body). Confirm Acknowledge's "stay unresolved" behavior is described consistently in both triage-patterns.md (the Acknowledge section itself + the Resolve-the-thread exception) and stop-conditions.md (the Complement-zero-unresolved note).
2. **Cross-reference link check** — triage-patterns.md's Acknowledge section references stop-conditions.md; stop-conditions.md's mode-shift paragraph references triage-patterns.md. Both directions resolve to existing (or newly-added) section headings.
3. **Grep sweep** — search for `apply, dismiss, clarify, or defer` (the old four-way enumeration) across the three files; should appear 0 times after edits. Confirm `apply, dismiss, clarify, defer, or acknowledge` (or variants like `apply, dismiss, clarify, defer, acknowledge` in the triage-patterns.md title) appears in the expected places.
4. **Copilot review loop** — run the normal drill per the skill itself. Dogfood the skill (including — recursively — the new Acknowledge category) on the PR.

No automated tests. No code changes.

## Out-of-scope / follow-ups

Issues from the same batch that are explicitly NOT addressed in the implementation PR this spec describes:

- **#4** (reply+resolve helper script)
- **#6** (outside-the-repo blockers escalation guidance)
- **#7** (worktree cleanup)

Each will get its own follow-up PR.
