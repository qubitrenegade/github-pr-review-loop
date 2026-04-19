---
name: github-pr-review-loop
description: Drives a GitHub pull request through its Copilot review loop to merge. Triages each reviewer comment into apply (fix + cite commit SHA), dismiss (reply with empirical evidence), clarify (ask when ambiguous), or defer (valid but out of scope — file a follow-up issue). Uses the GitHub GraphQL requestReviews mutation to re-trigger Copilot after pushing fixes, and resolveReviewThread to close each thread loop. Checks every required CI check is green before considering merge. Stops when Copilot returns zero new findings or starts repeating itself. Scales to multi-PR batch rollouts via parallel worktrees and scheduled wake-ups. Use when a PR has an open Copilot review that needs to be driven to merge, when a batch of related issues needs to be shipped across many PRs, or when deciding whether a Copilot finding is legitimate or a hallucination.
---

# GitHub PR Review Loop

Drive a PR (or many PRs in parallel) through the Copilot review loop to
merge. The habit is the same at every scale: push a change, wait for
Copilot, triage every finding, reply with a commit SHA when you fixed it
and empirical evidence when you didn't, re-request review via the GraphQL
mutation, stop when the signal goes quiet.

## When to reach for this skill

- A PR is open on a GitHub repo that has Copilot PR reviewer enabled.
- Copilot has left (or is about to leave) inline comments you need to
  process correctly rather than thrash on.
- You're tackling a batch of related issues and want to run multiple
  review loops in parallel without them stepping on each other.

If the repo has no Copilot reviewer or the PR has no reviewer assigned,
this skill doesn't apply — standard PR-review habits are fine.

## The triage — apply, dismiss, clarify, or defer

Every Copilot inline comment is one of four things. Decide explicitly;
don't guess.

**Apply** — the finding is real. Fix it in a follow-up commit, push,
then reply to the comment thread citing the commit SHA so the thread is
navigable when a human skims:

> Fixed in `abc1234` — <one-sentence summary of the fix>.

**Dismiss** — the finding is wrong (hallucination, stale claim, or
a suggestion that contradicts an intentional design choice). Reply with
evidence, not just an opinion:

> Dismissing — verified empirically: `grep -c 'foo' src/bar.py` returns
> 3, so the "foo is never referenced" claim is incorrect.

The evidence format depends on the claim. For "this function doesn't
exist" use `grep` or `python -c "import x; x.y"`. For "this would
crash" run the actual import or the unit test. For "the anchor
doesn't resolve" check the file for the heading. See
[references/triage-patterns.md](references/triage-patterns.md) for the
full catalog.

**Clarify** — the finding is ambiguous or you can't tell yet. Ask in
the thread rather than guessing. Usually a one-liner is enough:

> What specifically would "improve the error path"? The current
> `ConfigError` already names the key and the offending path; I'm
> not sure which surface you want changed.

**Defer** — the finding is correct but fixing it is out of scope for
the current PR. File a follow-up issue, link it in the reply, move
on. Example: Copilot flags a subtle race condition in code the PR
touches but doesn't change; the right fix is a dedicated cycle with
its own tests, not a drive-by patch in a PR focused on something else.

> Valid concern. Filed as #N for a dedicated cycle; out of scope
> for this PR which is focused on <X>. The proposed change would
> <consequence outside this PR's scope>.

`Defer` is a special case of `Apply` where the "apply" happens in a
separate PR. Same discipline: evidence that the finding is real,
explicit link to the follow-up so it isn't forgotten.

## After replying, resolve the conversation

Every review-comment thread on a PR has a "Resolve conversation"
button in the GitHub UI (and a `resolveReviewThread` GraphQL
mutation — see `references/graphql-snippets.md`). After you reply
with an apply-SHA, a dismissal, or a clarify question the reviewer
answers, **mark the thread resolved**. Three reasons:

- The PR's "unresolved conversations" count is a stop-condition
  signal all by itself. If it's 0, reviewers skimming the PR can
  trust that every thread was closed loop.
- A resolved thread collapses by default in the UI, so when you or
  a human reviewer scroll the PR later, you only see threads that
  still need attention.
- It's the same muscle memory as "close an issue" when the work is
  done. Orphaned open threads rot.

For `Clarify`, resolve only after the reviewer answers and you've
either Applied or Dismissed the answer. For `Defer`, resolve after
filing the follow-up issue and linking it — the current PR's thread
is closed because its disposition is settled, even if the fix lives
elsewhere.

## How to re-trigger review after pushing fixes

**Never @-mention the reviewer in a comment to re-request review.**
That does nothing for bot reviewers. The only mechanism that actually
re-triggers Copilot is the GraphQL `requestReviews` mutation:

```bash
BOT_ID="BOT_kgDOCnlnWA"  # Copilot's global node ID on github.com (see below)
PR_ID=$(gh pr view <PR_NUM> --repo <owner>/<repo> --json id --jq .id)
gh api graphql -f query='
  mutation($prId: ID!, $botId: ID!) {
    requestReviews(input: {pullRequestId: $prId, botIds: [$botId]}) {
      pullRequest { number }
    }
  }' -f prId="$PR_ID" -f botId="$BOT_ID"
```

`BOT_kgDOCnlnWA` is the observed github.com value. On GitHub
Enterprise or if the ID has rotated, discover it dynamically from an
existing Copilot review — see
[references/graphql-snippets.md](references/graphql-snippets.md)
for the discovery query and the rest of the catalog (list comments,
batch-reply, list/resolve threads, check CI status).

Re-request **after** your fix commits have pushed, not before. Copilot
reviews against the current HEAD of the PR branch; requesting a review
before your commit lands wastes a pass.

## The loop

For a single PR, the loop is this. Repeat until a stop condition fires.

1. Read the latest Copilot review's inline comments.
2. Triage each comment (apply / dismiss / clarify / defer).
3. Commit all "apply" fixes in one push (batch them — multiple reply
   cycles per push is wasteful).
4. Post inline replies with commit SHAs / empirical dismissals /
   follow-up issue links. Resolve each thread after replying.
5. Re-request review via GraphQL mutation.
6. Wait. Use `ScheduleWakeup` (Claude Code) or a cron / cadence —
   never busy-poll. 4-5 min is a sensible interval.
7. On wake-up, check status: any new CI failures? any new inline
   comments? any already-addressed comments Copilot re-raised?
8. Return to step 1 with the new findings, OR fire a stop condition.

## Before merging: CI must be green

**A stop condition firing is not permission to merge — it's permission
to stop chasing Copilot.** The merge gate is separate: every required
CI check on the PR head must be in `SUCCESS` or `SKIPPED` state.

```bash
gh pr view <PR_NUM> --repo <owner>/<repo> --json statusCheckRollup --jq \
  '{failed: [.statusCheckRollup[]? | select(.conclusion=="FAILURE") | .name],
    pending: [.statusCheckRollup[]? | select(.status!="COMPLETED") | .name]}'
```

If `failed` is non-empty: either fix the code (likely — the CI is
telling you something real) or fix the workflow (if the failure
reproduces on `main` unchanged, it's pre-existing infra, not this
PR's fault — but don't merge past it; file or fix the infra in a
dedicated PR first).

If `pending` is non-empty: wait. Don't merge mid-CI. Schedule another
wake-up.

Both empty → CI is green → merge is gated only on Copilot signal
(stop conditions) and human approval if required.

**Never use `gh pr merge --admin` to bypass a failing required check
just because "main is also failing so it's not my PR's fault".** If
main is red for the same reason, main shouldn't merge either —
that's a broken gate, fix it first. See
[references/stop-conditions.md](references/stop-conditions.md) under
"Failure-mode stops" for the clickwork Release-smoke episode that
taught this lesson the hard way.

## Stop conditions

Stop when any of these fires. Don't keep chasing.

- **Copilot's latest review returned zero new inline comments.** The
  most reliable signal. One clean pass means the reviewer is done.
- **Copilot is repeating itself.** The new finding is substantively the
  same as one you already replied to with a commit SHA or a dismissal.
  Reply pointing at the original thread ("addressed in `abc1234`, see
  thread above") and move on; don't change code.
- **Suggestions are drying up in volume.** Round 1 had 7 findings,
  round 3 had 2, round 4 has 1 — the signal is consumed. Next pass is
  usually empty.
- **The user says "merge it".** Explicit off-ramp, always valid.

See [references/stop-conditions.md](references/stop-conditions.md) for
the full list including failure-mode stops (reviewer is hallucinating
at high volume, thread has devolved, etc.).

## What to never do

- **Never @-mention the reviewer in a comment to re-request review.**
  Use the GraphQL mutation.
- **Never `--admin`-merge over a failing CI check** unless the check is
  demonstrably broken and you understand why. If the check is legitimately
  red, fix the underlying cause (the code, the test, or the workflow) and
  merge on green. Bypassing CI because it's "inconvenient" is how
  regressions ship.
- **Never dismiss a Copilot comment without evidence** just because it
  feels wrong. A one-line `python -c` or `grep -c` is cheap; use it.
- **Never change code to silence a repeated Copilot comment** if you've
  already replied to the original thread. Point at the first reply and
  move on.

## Keep PRs small and focused

Every principle above works better on small PRs. Why:

- Copilot review quality degrades on large diffs — the reviewer has
  more surface to skim, produces more low-signal findings, and the
  round count goes up without the signal going up.
- Smaller PRs mean shorter review loops (fewer findings per round,
  fewer rounds to converge), so throughput goes up even though PR
  count does too.
- A focused PR has a single clear Defer boundary — "this PR is
  about X; anything else → follow-up issue". Mega-PRs blur the
  boundary and Copilot's scope-related suggestions become harder
  to triage.
- Reverts and bisects are cheap on small PRs, expensive on big ones.

When a wave's plan shows one issue ballooning past ~300 lines of
diff or touching more than 3-4 files (outside of test files), split
it into follow-up issues before writing code, not after. See
[references/wave-orchestration.md](references/wave-orchestration.md)
for planning patterns and
[references/triage-patterns.md](references/triage-patterns.md)
under "Defer" for the right-sized escape hatch once you're mid-PR
and a finding would balloon the scope.

## Plan the waves before opening PRs

For any multi-PR rollout, the discipline starts before the first
implementation PR: **write the roadmap as its own PR, merge it,
write each wave plan as its own PR, merge each**. Every layer gets
reviewed before code lands under it.

- Roadmap PR pins wave structure, parallelism policy, release
  target, any cross-cutting decisions.
- Each wave's plan PR pins per-issue API shapes, branch names,
  TDD targets, and any wave-internal merge-order constraints.
- Only after the wave plan merges do the implementation PRs open.

This prevents the expensive mid-wave pivot where three subagents
have shipped diffs that contradict each other because the API
shape wasn't locked. It also means the maintainer reviews intent
at plan time — cheap — rather than discovering it in code review
of 5 concurrent PRs — expensive.

See [references/wave-orchestration.md](references/wave-orchestration.md)
for the full hierarchy (roadmap → wave plan → implementation PRs)
with concrete examples from the clickwork 1.0 cycle.

### Pairs well with superpowers:brainstorming

The "lock API shape upfront" part of wave planning is a
brainstorming exercise: what are the open questions, what are the
A/B/C options for each, which does the maintainer pick. The
`superpowers:brainstorming` skill is built for exactly this kind
of up-front design conversation — invoke it before writing the
roadmap or wave plan PR to surface the open decisions and get them
answered before code starts. This skill's review loop then drives
the resulting PRs to merge.

## Scaling to multiple PRs

The same loop runs for each PR in a multi-PR rollout. What changes is
the orchestration around it.

- One worktree per PR, branched from current main. Isolates concurrent
  edits so a change in PR #5 doesn't bleed into PR #7.
- Scheduled wake-ups per PR at staggered intervals so you're not blocked
  on one PR's Copilot round when the others could be progressing.
- Overlap the next wave's prep (branch creation, agent briefing) with
  the current wave's Copilot bake time. Don't idle.

See [references/wave-orchestration.md](references/wave-orchestration.md)
for the parallel-waves pattern in detail.

## Concrete example

The [clickwork 1.0.0
case study](references/case-study-clickwork-1.0.md) walks through a real
24-issue rollout across 4 planning waves + a release cut, ~25 PRs total.
Every principle above shows up in the narrative with commit SHAs and real
Copilot transcripts — useful as ground truth when deciding whether this
skill's generalisation actually applies to your situation.

## Troubleshooting

**Copilot won't review after a `requestReviews` call.** Check the PR's
"Reviewers" sidebar: if Copilot isn't listed, the repo hasn't been
enabled for Copilot PR review. Turn it on in repo settings → Pull
Requests → "Copilot review".

**`BOT_kgDOCnlnWA` gives a "User not found" error.** You used `userIds`
instead of `botIds` in the mutation. Copilot is a bot, not a user;
userIds will always 404 for it.

**CI failures repeat across pushes but aren't from my code.** If the
same workflow fails on `main` too, it's infra (bad cache, flaky
external service, broken workflow YAML). Fix the workflow in a
dedicated PR before expecting clean CI on the current one. Don't admin-
merge past it — that's the anti-pattern in "What to never do".
