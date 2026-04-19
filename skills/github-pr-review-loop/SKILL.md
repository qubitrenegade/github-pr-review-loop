---
name: github-pr-review-loop
description: Drives a GitHub pull request through its Copilot review loop to merge. Triages each reviewer comment into apply (fix + cite commit SHA), dismiss (reply with empirical evidence), or clarify. Uses the GitHub GraphQL requestReviews mutation to re-trigger Copilot after pushing fixes. Stops when Copilot returns zero new findings or starts repeating itself. Scales to multi-PR batch rollouts via parallel worktrees and scheduled wake-ups. Use when a PR has an open Copilot review that needs to be driven to merge, when a batch of related issues needs to be shipped across many PRs, or when deciding whether a Copilot finding is legitimate or a hallucination.
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

## The triage — apply, dismiss, or clarify

Every Copilot inline comment is one of three things. Decide explicitly;
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

## How to re-trigger review after pushing fixes

**Never @-mention the reviewer in a comment to re-request review.**
That does nothing for bot reviewers. The only mechanism that actually
re-triggers Copilot is the GraphQL `requestReviews` mutation:

```bash
BOT_ID="BOT_kgDOCnlnWA"  # Copilot's global node ID on github.com
PR_ID=$(gh pr view <PR_NUM> --repo <OWNER/REPO> --json id --jq .id)
gh api graphql -f query='
  mutation($prId: ID!, $botId: ID!) {
    requestReviews(input: {pullRequestId: $prId, botIds: [$botId]}) {
      pullRequest { number }
    }
  }' -f prId="$PR_ID" -f botId="$BOT_ID"
```

See [references/graphql-snippets.md](references/graphql-snippets.md) for
the full GraphQL catalog (list Copilot comments, batch-reply, dismiss
outstanding).

Re-request **after** your fix commits have pushed, not before. Copilot
reviews against the current HEAD of the PR branch; requesting a review
before your commit lands wastes a pass.

## The loop

For a single PR, the loop is this. Repeat until a stop condition fires.

1. Read the latest Copilot review's inline comments.
2. Triage each comment (apply / dismiss / clarify).
3. Commit all "apply" fixes in one push (batch them — multiple reply
   cycles per push is wasteful).
4. Post inline replies with commit SHAs / empirical dismissals.
5. Re-request review via GraphQL mutation.
6. Wait. Use `ScheduleWakeup` (Claude Code) or a cron / cadence —
   never busy-poll. 4-5 min is a sensible interval.
7. On wake-up, check status: any new CI failures? any new inline
   comments? any already-addressed comments Copilot re-raised?
8. Return to step 1 with the new findings, OR fire a stop condition.

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
24-issue rollout across 4 waves and 19 PRs. Every principle above shows
up in the narrative with commit SHAs and real Copilot transcripts —
useful as ground truth when deciding whether this skill's generalisation
actually applies to your situation.

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
